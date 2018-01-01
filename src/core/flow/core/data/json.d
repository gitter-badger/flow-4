module flow.core.data.json;

private import flow.core.data.engine;
private import flow.core.util;
private import std.json;
private import std.range;
private import std.traits;
private import std.variant;

private JSONValue jsonValue(Variant t, PropertyInfo pi) {
    import flow.core.data.engine : Data, TypeDesc;
    import std.datetime : DateTime, Date, Duration;
    import std.uuid : UUID;

    if(pi.array) {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            return t.get!(bool[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            return t.get!(byte[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            return t.get!(ubyte[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            return t.get!(short[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            return t.get!(ushort[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            return t.get!(int[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            return t.get!(uint[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            return t.get!(long[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            return t.get!(ulong[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            return t.get!(float[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            return t.get!(double[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            return t.get!(char[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            return t.get!(wchar[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            return t.get!(dchar[]).jsonValue;
        else if(pi.desc == TypeDesc.UUID)
            return t.get!(UUID[]).jsonValue;
        else if(pi.desc == TypeDesc.DateTime)
            return t.get!(DateTime[]).jsonValue;
        else if(pi.desc == TypeDesc.Date)
            return t.get!(Date[]).jsonValue;
        else if(pi.desc == TypeDesc.Duration)
            return t.get!(Duration[]).jsonValue;
        else if(pi.desc == TypeDesc.String)
            return t.get!(string[]).jsonValue;
        else if(pi.desc == TypeDesc.Data)
            return t.get!(Data[]).jsonValue;
        else assert(false, "this is an impossible situation");
    } else {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            return t.get!(bool).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            return t.get!(byte).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            return t.get!(ubyte).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            return t.get!(short).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            return t.get!(ushort).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            return t.get!(int).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            return t.get!(uint).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            return t.get!(long).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            return t.get!(ulong).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            return t.get!(float).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            return t.get!(double).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            return t.get!(char).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            return t.get!(wchar).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            return t.get!(dchar).jsonValue;
        else if(pi.desc == TypeDesc.UUID)
            return t.get!(UUID).jsonValue;
        else if(pi.desc == TypeDesc.DateTime)
            return t.get!(DateTime).jsonValue;
        else if(pi.desc == TypeDesc.Date)
            return t.get!(Date).jsonValue;
        else if(pi.desc == TypeDesc.Duration)
            return t.get!(Duration).jsonValue;
        else if(pi.desc == TypeDesc.String)
            return t.get!(string).jsonValue;
        else if(pi.desc == TypeDesc.Data)
            return t.get!(Data).jsonValue;
        else assert(false, "this is an impossible situation");
    }
}

private JSONValue jsonValue(T)(T arr)
if(
    isArray!T &&
    (
        is(ElementType!T : Data) ||
        is(ElementType!T == std.uuid.UUID) ||
        is(ElementType!T == std.datetime.DateTime) ||
        is(ElementType!T == std.datetime.Date) ||
        is(ElementType!T == std.datetime.Duration)
    )
) {
    import std.json : JSONValue;
    import std.range : empty;

    if(!arr.empty) {
        JSONValue[] cArr;
        foreach(e; arr) cArr ~= e.jsonValue;

        return JSONValue(cArr);
    } else return JSONValue(null);
}

private JSONValue jsonValue(T)(T arr)
if(
    isArray!T &&
    canHandle!(ElementType!T) &&
    !is(T == string) &&
    !is(ElementType!T : Data) &&
    !is(ElementType!T == std.uuid.UUID) &&
    !is(ElementType!T == std.datetime.DateTime) &&
    !is(ElementType!T == std.datetime.Date) &&
    !is(ElementType!T == std.datetime.Duration) &&
    !is(ElementType!T == ubyte)
) {
    import std.json : JSONValue;
    import std.range : empty;

    if(!arr.empty) {
        JSONValue[] cArr;
        foreach(e; arr) cArr ~= JSONValue(e);

        return JSONValue(cArr);
    } else return JSONValue(null);
}

private JSONValue jsonValue(T)(T arr)
if(
    isArray!T &&
    is(ElementType!T == ubyte)
) {
    import std.base64 : Base64;
    import std.json : JSONValue;
    import std.range : empty;

    if(!arr.empty) {
        string b64 = Base64.encode(arr);
        return JSONValue(b64);
    } else return JSONValue(null);
}

private JSONValue jsonValue(T)(T val)
if(
    canHandle!T &&
    !is(T : Data) &&
    !is(T == float) &&
    !is(T == double) &&
    !is(T == std.uuid.UUID) &&
    !is(T == std.datetime.DateTime) &&
    !is(T == std.datetime.Date) &&
    !is(T == std.datetime.Duration)
) {
    import std.json : JSONValue;

    return val is T.init ? JSONValue(null) : JSONValue(val);
}

private JSONValue jsonValue(T)(T val)
if(
    is(T == float) ||
    is(T == double)
) {
    import std.json : JSONValue;
    import std.math : isNaN;

    return val is T.init || isNaN(val) ? JSONValue(null) : JSONValue(val);
}

private JSONValue jsonValue(T)(T val)
if(is(T == std.uuid.UUID)) {
    import std.json : JSONValue;

    return val is T.init ? JSONValue(null) : JSONValue(val.toString());
}

private JSONValue jsonValue(T)(T val)
if(
    is(T == std.datetime.DateTime) ||
    is(T == std.datetime.Date)
) {
    import std.json : JSONValue;

    return val is T.init ? JSONValue(null) : JSONValue(val.toISOExtString());
}

private JSONValue jsonValue(T)(T val)
if(is(T == std.datetime.Duration)) {
    import std.json : JSONValue;

    return val is T.init ? JSONValue(null) : JSONValue(val.total!"hnsecs");
}

private JSONValue jsonValue(T)(T data)
if(is(T : Data)) {
    import flow.core.data.engine : PropertyInfo;
    import flow.core.util.templates : as;
    import std.json : JSONValue;

    JSONValue c;
    if(data !is null) {
        c = JSONValue(["dataType" : JSONValue(data.dataType)]);

        foreach(prop; data.properties) {
            auto pi = prop.as!PropertyInfo;
            auto val = pi.get(data);
            auto j = val.jsonValue(pi);
            if(!j.isNull) c.object[pi.name] = j;
        }
    }

    return c;
}

/// json serializer types
enum JsonSerializer {
    StdJson
}

/// jsonifies a data object
string json(T)(T data, bool pretty = false, JsonSerializer serializer = JsonSerializer.StdJson) {
    import flow.core.util.error : NotImplementedError;

    switch(serializer) {
        case JsonSerializer.StdJson:
            return pretty ? data.jsonValue.toPrettyString : data.jsonValue.toString;
        default:
            throw new NotImplementedError;
    }
}

/// thrown when given json is invalid
class InvalidJsonException : Exception {
    /// ctor
    this(string msg){super(msg);}
}

/// create a data object from json
Data createDataFromJson(string str, JsonSerializer serializer = JsonSerializer.StdJson) {
    import flow.core.util.error : NotImplementedError;
    import std.json : parseJSON;

    switch(serializer) {
        case JsonSerializer.StdJson:
            return str.parseJSON.createData;
        default:
            throw new NotImplementedError;
    }
}

private Data createData(JSONValue j) {
    import flow.core.data.engine : createData, Data, PropertyInfo;
    import flow.core.util.templates : as;
    import std.datetime : DateTime, Date, Duration;
    import std.uuid : UUID;
    import std.variant : Variant;
    
    auto dt = j["dataType"].str;
    if(dt == string.init)
        throw new InvalidJsonException("json object has no dataType");

    auto d = createData(dt);
    foreach(string name, e; j) {
        if(name != "dataType") {
            if(name !in d.properties)
                throw new InvalidJsonException("\""~d.dataType~"\" contains no property named \""~name~"\"");
        
            auto pi = d.properties[name].as!PropertyInfo;
            Variant val;
            if(!val.hasValue) val = e.get!bool(d, pi);
            if(!val.hasValue) val = e.get!byte(d, pi);
            if(!val.hasValue) val = e.get!ubyte(d, pi);
            if(!val.hasValue) val = e.get!short(d, pi);
            if(!val.hasValue) val = e.get!ushort(d, pi);
            if(!val.hasValue) val = e.get!int(d, pi);
            if(!val.hasValue) val = e.get!uint(d, pi);
            if(!val.hasValue) val = e.get!long(d, pi);
            if(!val.hasValue) val = e.get!ulong(d, pi);
            if(!val.hasValue) val = e.get!float(d, pi);
            if(!val.hasValue) val = e.get!double(d, pi);
            if(!val.hasValue) val = e.get!char(d, pi);
            if(!val.hasValue) val = e.get!wchar(d, pi);
            if(!val.hasValue) val = e.get!dchar(d, pi);
            if(!val.hasValue) val = e.get!UUID(d, pi);
            if(!val.hasValue) val = e.get!DateTime(d, pi);
            if(!val.hasValue) val = e.get!Date(d, pi);
            if(!val.hasValue) val = e.get!Duration(d, pi);
            if(!val.hasValue) val = e.get!string(d, pi);
            if(!val.hasValue)
                val = e.get!Data(d, pi);

            if(val.hasValue)
                pi.set(d, val);
        }
    }

    return d;
}

private Variant get(T)(JSONValue j, Data d, PropertyInfo pi)
if(
    canHandle!T &&
    !is(T : Data)
) {
    import flow.core.util.templates : as;
    import std.base64 : Base64;
    import std.datetime : DateTime, Date, Duration, hnsecs;
    import std.json : JSON_TYPE;
    import std.uuid : UUID, parseUUID;
    import std.traits : isScalarType;
    import std.variant : Variant;
    
    if(pi.info == typeid(T)) {
        switch(j.type) {
            case JSON_TYPE.ARRAY:
                    T[] val;
                    foreach(size_t i, e; j)
                        val ~= e.get!T(d ,pi).get!T();
                return Variant(val);
            case JSON_TYPE.STRING:
                static if(is(T == string))
                    return Variant(j.str);
                else static if(is(T == ubyte)) {
                    if(pi.array) {
                        ubyte[] arr;
                        if(j.str != string.init)
                            arr = Base64.decode(j.str);
                        return Variant(arr);
                    } else throw new InvalidJsonException("\""~d.dataType~"\" property \""~pi.name~"\" type mismatching");
                }
                else static if(is(T == DateTime) || is(T == Date))
                    return Variant(T.fromISOString(j.str));
                else static if(is(T == Duration))
                    return Variant(j.integer.hnsecs);
                else static if(is(T == UUID))
                    return Variant(j.str.parseUUID);
                else return Variant();
            case JSON_TYPE.INTEGER:
                static if(isScalarType!T)
                    return Variant(j.integer.as!T);
                else return Variant();
            case JSON_TYPE.UINTEGER:
                static if(isScalarType!T)
                    return Variant(j.uinteger.as!T);
                else return Variant();
            case JSON_TYPE.FLOAT:
                static if(isScalarType!T)
                    return Variant(j.floating.as!T);
                else return Variant();
            case JSON_TYPE.TRUE:
                static if(is(T : bool))
                    return Variant(true);
                else return Variant();
            case JSON_TYPE.FALSE:
                static if(is(T : bool))
                    return Variant(false);
                else return Variant();
            default:
                throw new InvalidJsonException("\""~d.dataType~"\" property \""~pi.name~"\" type mismatching");
        }
    } else return Variant();
}

private Variant get(T)(JSONValue j, Data d, PropertyInfo pi)
if(is(T : Data)) {
    import flow.core.data.engine : Data, TypeDesc;
    import std.json : JSON_TYPE;
    import std.variant : Variant;

    if(pi.desc & TypeDesc.Data) {
        switch(j.type) {
            case JSON_TYPE.ARRAY:
                    T[] val;
                    foreach(size_t i, e; j)
                        val ~= e.get!T(d ,pi).get!T();
                return Variant(val);
            case JSON_TYPE.OBJECT:
                static if(is(T : Data))
                    return Variant(j.createData());
                else return Variant();
            default:
                throw new InvalidJsonException("\""~d.dataType~"\" property \""~pi.name~"\" type mismatching");
        }
    } else return Variant();
}

unittest { test.header("data.json: json serialization of data and member");
    import flow.core.data.engine : TestData, InheritedTestData, TestEnum;
    import flow.core.util.templates : as;
    import std.json : parseJSON;
    import std.uuid : parseUUID;

    auto d = new InheritedTestData;
    d.boolean = true;
    d.uinteger = 5;
    d.text = "foo";
    d.uuid = "1bf8eac7-64ee-4cde-aa9e-8877ac2d511d".parseUUID;
    d.inner = new TestData;
    d.inner.integer = 3;
    d.enumeration = TestEnum.Bar;
    d.uintegerA = [3, 4];
    d.textA = ["foo", "bar"];
    d.innerA = [new TestData, new TestData];
    d.enumerationA = [TestEnum.Bar, TestEnum.Foo];
    d.additional = "ble";
    d.ubyteA = [1, 2, 4, 8, 16, 32, 64, 128];

    auto dStr = d.json;
    auto templ = "{"~
        "\"additional\":\"ble\","~
        "\"boolean\":true,"~
        "\"dataType\":\"flow.core.data.engine.InheritedTestData\","~
        "\"enumeration\":1,"~
        "\"enumerationA\":[1,0],"~
        "\"inner\":{"~
            "\"dataType\":\"flow.core.data.engine.TestData\","~
            "\"integer\":3"~
        "},"~
        "\"innerA\":["~
            "{\"dataType\":\"flow.core.data.engine.TestData\"},"~
            "{\"dataType\":\"flow.core.data.engine.TestData\"}"~
        "],"~
        "\"text\":\"foo\","~
        "\"textA\":[\"foo\",\"bar\"],"~
        "\"ubyteA\":\"AQIECBAgQIA=\","~
        "\"uinteger\":5,"~
        "\"uintegerA\":[3,4],"~
        "\"uuid\":\"1bf8eac7-64ee-4cde-aa9e-8877ac2d511d\"}";
    debug(data) {import std.stdio : writeln; writeln(templ);}
    debug(data) {import std.stdio : writeln; writeln(dStr);}
    assert(dStr == templ, "could not serialize data to json");

    auto d2 = parseJSON(dStr).createData.as!InheritedTestData;
    assert(d2 !is null, "could not deserialize data");
    assert(d2.boolean, "could not deserialize basic scalar value");
    assert(d2.uinteger == 5, "could not deserialize basic scalar value");
    assert(d2.text == "foo", "could not deserialize basic string value");   
    assert(d2.uuid == "1bf8eac7-64ee-4cde-aa9e-8877ac2d511d".parseUUID, "could not deserialize basic uuid value");
    assert(d2.inner !is null && d2.inner !is d.inner, "could not deserialize basic data value");
    assert(d2.enumeration == TestEnum.Bar, "could not deserialize basic enum value");
    assert(d2.inner.integer == 3, "could not deserialize property of basic data value");
    assert(d2.uintegerA.length == 2 && d2.uintegerA[0] == 3 && d2.uintegerA[1] == 4 && d2.uintegerA !is d.uintegerA, "could not deserialize array scalar value");
    assert(d2.textA.length == 2 && d2.textA[0] == "foo" && d2.textA[1] == "bar", "could not deserialize array string value");
    assert(d2.innerA.length == 2 && d2.innerA[0] !is null && d2.innerA[1] !is null && d2.innerA[0] !is d2.innerA[1] && d2.innerA[0] !is d.innerA[0], "could not set array data value");
    assert(d2.enumerationA.length == 2 && d2.enumerationA[0] == TestEnum.Bar && d2.enumerationA[1] == TestEnum.Foo, "could not deserialize array enum value");

    assert(d2.additional == "ble", "could not deserialize basic scalar value");
test.footer(); }