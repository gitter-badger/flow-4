module flow.core.data.dynamic;

private import flow.core.data.engine;
private import flow.core.util;
private import std.range;
private import std.traits;
private import std.variant;

/// is thrown when a requested or required property is not existing
class PropertyNotExistingException : Exception {
    /// ctro
    this(){super(string.init);}
}

private Variant get(Data d, string name){
    import flow.core.data.engine : PropertyInfo;
    import flow.core.util.templates : as;

    if(name in d.properties)
        return d.properties[name].as!PropertyInfo.get(d);
    else
        throw new PropertyNotExistingException;
}

/// get property as data
T get(T)(Data d, string name)
if(is(T : Data)) {
    import flow.core.data.engine : Data;
    import flow.core.util.templates : as;

    return d.get(name).get!Data().as!T;
}

/// get property as data array
T get(T)(Data d, string name)
if(
    isArray!T &&
    is(ElementType!T : Data)
) {
    import flow.core.data.engine : Data;
    import flow.core.util.templates : as;

    return d.get(name).get!(Data[])().as!T;
}

/// get property as supported type
T get(T)(Data d, string name)
if(
    canHandle!T &&
    !is(T : Data)
) {
    import std.traits : OriginalType;

    return cast(T)d.get(name).get!(OriginalType!T)();
}

/// get property as supported array
T get(T)(Data d, string name)
if(
    !is(T == string) &&
    isArray!T &&
    canHandle!(ElementType!T) &&
    !is(ElementType!T : Data)
) {
    import std.range : ElementType;
    import std.traits : OriginalType;

    return cast(T)d.get(name).get!(OriginalType!(ElementType!T)[])();
}

private bool set(Data d, string name, Variant val) {
    import flow.core.data.engine : PropertyInfo;
    import flow.core.util.templates : as;

    if(name in d.properties)
        return d.properties[name].as!PropertyInfo.set(d, val);
    else
        throw new PropertyNotExistingException;
}

/// set property using data
bool set(T)(Data d, string name, T val)
if(is(T : Data)) {
    import flow.core.data.engine : Data;
    import flow.core.util.templates : as;
    import std.variant : Variant;

    return d.set(name, Variant(val.as!Data));
}

/// set property using data array
bool set(T)(Data d, string name, T val)
if(
    isArray!T &&
    is(ElementType!T : Data)
) {
    import flow.core.data.engine : Data;
    import flow.core.util.templates : as;
    import std.variant : Variant;

    return d.set(name, Variant(val.as!(Data[])));
}

/// set property using supported type
bool set(T)(Data d, string name, T val)
if(
    canHandle!T &&
    !is(T : Data)
) {
    import std.traits : OriginalType;
    import std.variant : Variant;

    return d.set(name, Variant(cast(OriginalType!T)val));
}

/// set property using supported type array
bool set(T)(Data d, string name, T val)
if(
    !is(T == string) &&
    isArray!T &&
    canHandle!(ElementType!T) &&
    !is(ElementType!T : Data)
) {
    import std.range : ElementType;
    import std.traits : OriginalType;
    import std.variant : Variant;

    return d.set(name, Variant(cast(OriginalType!(ElementType!T)[])val));
}

unittest { test.header("gears.data: dynamic data usage");
    import flow.core.data.engine : createData, TestData, InheritedTestData, TestEnum;
    import flow.core.util.templates : as;
    import std.range : empty;

    auto d = fqn!InheritedTestData.createData().as!InheritedTestData;
    assert(d !is null, "could not dynamically create instance of data");
    assert(d.integer is long.init && d.integerA.empty, "data is not initialized correctly at dynamic creation");

    assert(d.set("floating", 0.005) && d.floating == 0.005, "could not set basic scalar value");
    assert(d.get!double("floating") == 0.005, "could not get basic scalar value");

    assert(d.set("uinteger", 4) && d.uinteger == 4, "could not set basic scalar value");
    assert(d.get!ulong("uinteger") == 4, "could not get basic scalar value");
    
    assert(d.set("text", "foo") && d.text == "foo", "could not set basic string value");
    assert(d.get!string("text") == "foo", "could not get basic string value");
    
    assert(d.set("inner", new TestData) && d.inner !is null, "could not set basic data value");
    assert(d.get!TestData("inner") !is null, "could not get basic data value");
    assert(d.set("inner", null.as!TestData) && d.inner is null, "could not set basic data value");
    assert(d.get!TestData("inner") is null, "could not get basic data value");

    assert(d.set("enumeration", TestEnum.Bar) && d.enumeration == TestEnum.Bar, "could not set basic enum value");
    assert(d.get!TestEnum("enumeration") == TestEnum.Bar, "could not get basic enum value");
    
    assert(d.set("integerA", [2L, 3L, 4L]) && d.integerA.length == 3 && d.integerA[0] == 2 && d.integerA[1] == 3 && d.integerA[2] == 4, "could not set array scalar value");
    assert(d.get!(long[])("integerA")[0] == 2L, "could not get array scalar value");
    
    assert(d.set("textA", ["foo", "bar"]) && d.textA.length == 2 && d.textA[0] == "foo" && d.textA[1] == "bar", "could not set array string value");
    assert(d.get!(string[])("textA")[0] == "foo", "could not get array string value");
    
    assert(d.set("innerA", [new TestData]) && d.innerA.length == 1 && d.innerA[0] !is null, "could not set array data value");
    assert(d.get!(TestData[])("innerA")[0] !is null, "could not get array data value");
    
    assert(d.set("enumerationA", [TestEnum.Bar, TestEnum.Foo]) && d.enumerationA.length == 2 && d.enumerationA[0] == TestEnum.Bar && d.enumerationA[1] == TestEnum.Foo, "could not set array enum value");
    assert(d.get!(TestEnum[])("enumerationA")[0] == TestEnum.Bar, "could not get array enum value");
    
    assert(d.set("additional", "ble") && d.additional == "ble", "could not set second level basic scalar value");
    assert(d.get!string("additional") == "ble", "could not get second level basic scalar value");
    
    assert(d.set("nanA", [double.nan]) && d.nanA.length == 1 && d.nanA[0] is double.nan, "could not set array data value");
    assert(d.get!(double[])("nanA")[0] is double.nan, "could not get array data value");
test.footer(); }