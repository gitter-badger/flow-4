module flow.core.data.engine;

private import std.variant;
private import std.range;
private import std.traits;
private import flow.core.data.mutex;
private import flow.core.util;
private import msgpack;

/// checks if data engine can handle a certain data type
template canHandle(T) {
    private import std.datetime;
    private import std.traits;
    private import std.uuid;

    enum canHandle =
        is(T == bool) ||
        is(T == byte) ||
        is(T == ubyte) ||
        is(T == short) ||
        is(T == ushort) ||
        is(T == int) ||
        is(T == uint) ||
        is(T == long) ||
        is(T == ulong) ||
        is(T == float) ||
        is(T == double) ||
        is(T == char) ||
        is(T == wchar) ||
        is(T == dchar) ||
        (is(T == enum) && is(OriginalType!T == bool)) ||
        (is(T == enum) && is(OriginalType!T == byte)) ||
        (is(T == enum) && is(OriginalType!T == ubyte)) ||
        (is(T == enum) && is(OriginalType!T == short)) ||
        (is(T == enum) && is(OriginalType!T == ushort)) ||
        (is(T == enum) && is(OriginalType!T == int)) ||
        (is(T == enum) && is(OriginalType!T == uint)) ||
        (is(T == enum) && is(OriginalType!T == long)) ||
        (is(T == enum) && is(OriginalType!T == ulong)) ||
        (is(T == enum) && is(OriginalType!T == float)) ||
        (is(T == enum) && is(OriginalType!T == double)) ||
        (is(T == enum) && is(OriginalType!T == char)) ||
        (is(T == enum) && is(OriginalType!T == wchar)) ||
        (is(T == enum) && is(OriginalType!T == dchar)) ||
        is(T == UUID) ||
        is(T == DateTime) ||
        is(T == Date) ||
        is(T == Duration) ||
        is(T == string) ||        
        is(T : Data);
}

/// returns the datatype string of data
//string fqn(Data d) {return d.dataType;}

/// describes the kind of data
enum TypeDesc {
    Scalar,
    UUID,
    DateTime,
    Date,
    Duration,
    String,
    Data
}

/// is thrown when a given type does not fit the expectation
class TypeMismatchException : Exception {
    /// ctor
    this(){super(string.init);}
}

/// runtime inforamtions of a data property
struct PropertyInfo {
	TypeInfo info;
    string type;
    string name;
    bool array;
    TypeDesc desc;

    Variant function(Data) getter;
	bool function(Data, Variant) setter;
	bool function(Data, Data) equals;
    void function(Data, ref Packer, ref string[][string]) bin;
    void function(Data, ref Unpacker, ref string[][string]) unbin;
	void function(Data) lockReader;
	void function(Data) lockWriter;
	void function(Data) unlockReader;
	void function(Data) unlockWriter;

    /// gets the value as variant
    Variant get(Data d) {
        return getter(d);
    }

    /// sets the value from a variant
    bool set(Data d, Variant v) {
        return setter(d, v);
    }

    /// checks if it equals for given data objects
    bool equal(Data a, Data b) {
        return equals(a, b);
    }
}

/// base class of all data
abstract class Data {
    /// returns all properties of data type
    @property shared(PropertyInfo[string]) properties(){return null;}

    @nonPacked protected DataMutex lock;
    @nonPacked DataMutex.Reader reader() {return this.lock.reader;}
    @nonPacked DataMutex.Writer writer() {return this.lock.writer;}

    /// returns data type name
    @nonPacked abstract @property string dataType();

    override bool opEquals(Object o) {
        import flow.core.util.templates : as;

        auto c = o.as!Data;
        if(c !is null && this.dataType == c.dataType) {
            foreach(pi; this.properties)
                if(!pi.as!PropertyInfo.equal(this, c)) {
                    return false;
                }
            
            return true;
        } else return false;
    }

    this() {
        import flow.core.util;

        RecursiveLocker rl;
        rl.readerLock = &this.readerLockChilds;
        rl.writerLock = &this.writerLockChilds;
        rl.readerUnlock = &this.readerUnlockChilds;
        rl.writerUnlock = &this.writerUnlockChilds;

        this.lock = new DataMutex(rl, DataMutex.Policy.PREFER_WRITERS);
    }

    void readerLockChilds() {
        foreach(pi; this.properties)
            pi.as!PropertyInfo.lockReader(this);
    }

    void writerLockChilds() {
        foreach(pi; this.properties)
            pi.as!PropertyInfo.lockWriter(this);
    }

    void readerUnlockChilds() {
        foreach(pi; this.properties)
            pi.as!PropertyInfo.unlockReader(this);
    }

    void writerUnlockChilds() {
        foreach(pi; this.properties)
            pi.as!PropertyInfo.unlockWriter(this);
    }

    /*override ulong toHash() {
        // TODO collect all hashes of properties and generate collective hash
        return super.toHash;
    }*/

    /// deep snaps data object (copies whole memory)
    @property Data snap() {
        import flow.core.util.templates : as;

        Data c = Object.factory(this.dataType).as!Data;

        foreach(prop; this.properties) {
            auto pi = prop.as!PropertyInfo;
            auto val = pi.get(this);
            pi.set(c, val.snap(pi));
        }

        return c;
    }
}

enum field;

/// mixin allowing to derrive from data
mixin template _data() {
    private static import ___flowutil = flow.core.util.templates, ___flowdata = flow.core.data.engine;
    private static import ___traits = std.traits;
    private static import ___range = std.range;

    //debug(data) pragma(msg, "\tdata "~___flowutil.fqn!(typeof(this)));

    shared static ___flowdata.PropertyInfo[string] Properties;
    override @property shared(___flowdata.PropertyInfo[string]) properties() {
        return typeof(this).Properties;
    }

    private static PropertyInfo getPropertyInfo(T, string name)()
    if (___flowdata.canHandle!T && (!___traits.isArray!T || is(T==string))) {
        import flow.core.util.templates : as;
        import msgpack : Packer, Unpacker;
        import std.datetime : DateTime, Date, Duration;
        import std.traits : OriginalType, isScalarType;
        import std.uuid : UUID;
        import std.variant : Variant;

        PropertyInfo pi;

        static if(isScalarType!T) {
            pi.type = OriginalType!(T).stringof;
            pi.info = typeid(OriginalType!T);
        } else {
            pi.type = T.stringof;
            pi.info = typeid(T);
        }

        pi.name = name;
        pi.array = false;
        
        mixin("pi.getter = (d) {
            auto t = d.as!(typeof(this));
            return Variant("~(is(T : Data) ?
                "t."~name~".as!Data" :
                "cast("~OriginalType!(T).stringof~")t."~name)~");
        };");
        
        mixin("pi.setter = (d, v) {
            auto t = d.as!(typeof(this));
            if(v.convertsTo!("~(is(T : Data) ? "Data" : OriginalType!(T).stringof)~")) {
                t."~name~" = cast("~T.stringof~")"~(is(T : Data) ?
                    "v.get!Data().as!"~T.stringof :
                    "v.get!("~OriginalType!(T).stringof~")")~";
                return true;
            } else return false;
        };");

        mixin("pi.equals = (a, b) {
            static if(is(T == float) || is(T == double)) {
                import std.math : isIdentical;
                
                return a.as!(typeof(this))."~name~".isIdentical(b.as!(typeof(this))."~name~");
            } else
                return a.as!(typeof(this))."~name~" == b.as!(typeof(this))."~name~";
        };");

        mixin("pi.bin = (Data d, ref Packer p, ref string[][string] ti) {
            auto t = d.as!(typeof(this));
            bin(t."~name~", p, ti);
        };");

        mixin("pi.unbin = (Data d, ref Unpacker u, ref string[][string] ti) {
            auto t = d.as!(typeof(this));
            t."~name~" = unbin!("~T.stringof~")(u, ti);
        };");

        pi.lockReader = (d) {
            static if(is(T : Data))
                d.reader.lock();
        };

        pi.lockWriter = (d) {
            static if(is(T : Data))
                d.writer.lock();
        };

        pi.unlockReader = (d) {
            static if(is(T : Data))
                d.reader.unlock();
        };

        pi.unlockWriter = (d) {
            static if(is(T : Data))
                d.writer.unlock();
        };

        if(isScalarType!T) pi.desc = TypeDesc.Scalar;
        else if(is(T : Data)) pi.desc = TypeDesc.Data;
        else if(is(T == UUID)) pi.desc = TypeDesc.UUID;
        else if(is(T == DateTime)) pi.desc = TypeDesc.DateTime;
        else if(is(T == Date)) pi.desc = TypeDesc.Date;
        else if(is(T == Duration)) pi.desc = TypeDesc.Duration;
        else if(is(T == string)) pi.desc = TypeDesc.String;

        return pi;
    }

    private static PropertyInfo getPropertyInfo(AT, string name)()
    if(
        ___traits.isArray!AT &&
        ___flowdata.canHandle!(___range.ElementType!AT) &&
        !is(AT == string)
    ) {
        import flow.core.util.templates : as;
        import msgpack : Packer, Unpacker;
        import std.datetime : DateTime, Date, Duration;
        import std.traits : OriginalType, isScalarType;
        import std.uuid : UUID;
        import std.range : ElementType;
        import std.variant : Variant;

        alias T = ElementType!AT;

        PropertyInfo pi;
        
        static if(isScalarType!T) {
            pi.type = OriginalType!(T).stringof;
            pi.info = typeid(OriginalType!T);
        } else {
            pi.type = T.stringof;
            pi.info = typeid(T);
        }
        
        pi.name = name;
        pi.array = true;

        mixin("pi.getter = (d) {
            auto t = d.as!(typeof(this));
            return Variant("~(is(T : Data) ?
                "t."~name~".as!(Data[])" :
                "cast("~OriginalType!(T).stringof~"[])t."~name)~");
        };");

        mixin("pi.setter = (d, v) {
            auto t = d.as!(typeof(this));
            if(v.convertsTo!("~(is(T : Data) ? "Data" : OriginalType!(T).stringof)~"[])) {
                t."~name~" = cast("~T.stringof~"[])"~(is(T : Data) ?
                    "v.get!(Data[])().as!("~T.stringof~"[])" :
                    "v.get!("~OriginalType!(T).stringof~"[])")~";
                return true;
            } else return false;
        };");

        mixin("pi.equals = (a, b) {            
            import std.algorithm.comparison : equal;
            static if(is(T == float) || is(T == double)) {
                import std.math : isIdentical;

                return a.as!(typeof(this))."~name~
                    ".equal!((x, y) => x.isIdentical(y))(b.as!(typeof(this))."~name~");
            } else {
                return a.as!(typeof(this))."~name~".equal(b.as!(typeof(this))."~name~");
            }
        };");

        mixin("pi.bin = (Data d, ref Packer p, ref string[][string] ti) {
            auto t = d.as!(typeof(this));
            bin(t."~name~", p, ti);
        };");

        mixin("pi.unbin = (Data d, ref Unpacker u, ref string[][string] ti) {
            auto t = d.as!(typeof(this));
            t."~name~" = unbin!("~AT.stringof~")(u, ti);
        };");

        pi.lockReader = (a) {
            static if(is(ElementType!T : Data))
                foreach(d; a)
                    d.reader.lock();
        };

        pi.lockWriter = (a) {
            static if(is(ElementType!T : Data))
                foreach(d; a)
                    d.writer.lock();
        };

        pi.unlockReader = (a) {
            static if(is(ElementType!T : Data))
                foreach(d; a)
                    d.reader.unlock();
        };

        pi.unlockWriter = (a) {
            static if(is(ElementType!T : Data))
                foreach(d; a)
                    d.writer.unlock();
        };

        if(isScalarType!T) pi.desc = TypeDesc.Scalar;
        else if(is(T : Data)) pi.desc = TypeDesc.Data;
        else if(is(T == UUID)) pi.desc = TypeDesc.UUID;
        else if(is(T == DateTime)) pi.desc = TypeDesc.DateTime;
        else if(is(T == Date)) pi.desc = TypeDesc.Date;
        else if(is(T == Duration)) pi.desc = TypeDesc.Duration;
        else if(is(T == string)) pi.desc = TypeDesc.String;

        return pi;
    }

    override @property string dataType() {return ___flowutil.fqn!(typeof(this));}
    
    shared static this() {
        import flow.core.util : as;
        import std.range : ElementType;
        import std.traits : hasUDA, isArray;

        static assert(is(typeof(this) : Data), "data has to be derrived from flow.core.data.engine.Data");
        debug(data) {import std.stdio : writeln; writeln(typeof(this).stringof);}

        foreach(m; __traits(allMembers, typeof(this))) {
            //static if(__traits(compiles, mixin("alias M = typeof(this)."~m~";"))) {
                mixin("alias M = typeof(this)."~m~";");
                //pragma(msg, "FFFFFFFFFFFF");
                static if(hasUDA!(M, field)) {
                    debug(data) {import std.stdio : writeln; writeln("\t", typeof(M).stringof, " ", M.stringof);}
                    Properties[M.stringof] = typeof(this).getPropertyInfo!(typeof(M), M.stringof).as!(shared(PropertyInfo));
                }
            //}
        }
        debug(data) {import std.stdio : writeln; writeln("");}
    }

    override @property typeof(this) snap() {
        return cast(typeof(this))super.snap;
    }
}

/// mixin creating a data field
mixin template fieldDeprecated(T, string _name) {
    // field
    mixin("@field "~T.stringof~" "~_name~";");
}

/// create a data object from its type name
Data createData(string name) {
    import flow.core.util.templates : as;

    return Object.factory(name).as!Data;
}

/// deep snap an array of data
T snap(T)(T arr)
if(
    isArray!T &&
    is(ElementType!T : Data)
) {
    import std.range : ElementType;
    
    T cArr;
    foreach(e; arr) cArr ~= cast(ElementType!T)e.snap;

    return cArr;
}

/// deep snap an array of supported type
T snap(T)(T arr)
if(
    isArray!T &&
    canHandle!(ElementType!T) &&
    !is(ElementType!T : Data)
) {
    T cArr;
    foreach(e; arr) cArr ~= e;

    return cArr;
}

private Variant snap(Variant t, PropertyInfo pi) {
    import std.datetime : DateTime, Date, Duration;
    import std.uuid : UUID;
    import std.variant : Variant;

    if(pi.array) {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            return Variant(t.get!(bool[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            return Variant(t.get!(byte[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            return Variant(t.get!(ubyte[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            return Variant(t.get!(short[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            return Variant(t.get!(ushort[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            return Variant(t.get!(int[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            return Variant(t.get!(uint[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            return Variant(t.get!(long[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            return Variant(t.get!(ulong[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            return Variant(t.get!(float[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            return Variant(t.get!(double[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            return Variant(t.get!(char[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            return Variant(t.get!(wchar[]).snap);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            return Variant(t.get!(dchar[]).snap);
        else if(pi.desc == TypeDesc.UUID)
            return Variant(t.get!(UUID[]).snap);
        else if(pi.desc == TypeDesc.DateTime)
            return Variant(t.get!(DateTime[]).snap);
        else if(pi.desc == TypeDesc.Date)
            return Variant(t.get!(Date[]).snap);
        else if(pi.desc == TypeDesc.Duration)
            return Variant(t.get!(Duration[]).snap);
        else if(pi.desc == TypeDesc.String)
            return Variant(t.get!(string[]).snap);
        else if(pi.desc == TypeDesc.Data)
            return Variant(t.get!(Data[]).snap);
        else assert(false, "this is an impossible situation");
    } else {
        if(pi.desc == TypeDesc.Data) {
            auto d = t.get!(Data);
            return Variant(d !is null ? d.snap : null);
        }
        else return t;
    }
}

version (unittest) enum TestEnum {
    Foo,
    Bar
}

version (unittest) class TestData : Data { mixin _data;
    import std.datetime : DateTime, Duration;
    import std.uuid : UUID;

    // testing basic fields
    //@field bool testFieldAttribute;
    @field TestData inner;
    @field bool boolean;
    @field long integer;
    @field ulong uinteger;
    @field double floating;
    @field TestEnum enumeration;
    @field UUID uuid;
    @field DateTime dateTime;
    @field Duration duration;
    @field string text;

    // testing array fields
    @field TestData[] innerA;
    @field bool[] booleanA;
    @field long[] integerA;
    @field ulong[] uintegerA;
    @field double[] floatingA;
    @field TestEnum[] enumerationA;
    @field UUID[] uuidA;
    @field DateTime[] dateTimeA;
    @field Duration[] durationA;
    @field string[] textA;

    // testing for module name conflicts
    @field string name;
    @field string flow;

    // nan != nan
    @field double nan;
    @field double[] nanA;

    // ubyte[] json as base64
    @field ubyte[] ubyteA;
}

version(unittest) class InheritedTestData : TestData { mixin _data;
    @field string additional;
}

unittest { test.header("data.engine: static data usage");
    import std.range : empty;
    
    auto d = new InheritedTestData;
    assert(d !is null, "could not statically create instance of data");
    assert(d.integer is long.init && d.integerA.empty && d.text is string.init && d.inner is null, "data is not initialized correctly at static creation");
    
    d.floating = 0.005; assert(d.floating == 0.005, "could not set basic scalar value");
    d.uinteger = 5; assert(d.uinteger == 5, "could not set basic scalar value");
    d.text = "foo"; assert(d.text == "foo", "could not set basic string value");    
    d.inner = new TestData; assert(d.inner !is null, "could not set basic data value");
    d.inner.integer = 3; assert(d.inner.integer == 3, "could not set property of basic data value");
    d.enumeration = TestEnum.Bar; assert(d.enumeration == TestEnum.Bar, "could not ser property of basic enum value");
    d.uintegerA ~= 3; d.uintegerA ~= 4; assert(d.uintegerA.length == 2 && d.uintegerA[0] == 3 && d.uintegerA[1] == 4, "could not set array scalar value");
    d.uintegerA = [1]; assert(d.uintegerA.length == 1 && d.uintegerA[0] == 1, "could not set array scalar value");
    d.textA ~= "foo"; d.textA ~= "bar"; assert(d.textA.length == 2 && d.textA[0] == "foo" && d.textA[1] == "bar", "could not set array string value");
    d.textA = ["bla"]; assert(d.textA.length == 1 && d.textA[0] == "bla", "could not set array string value");
    d.innerA ~= new TestData; d.innerA ~= new TestData; assert(d.innerA.length == 2 && d.innerA[0] !is null && d.innerA[1] !is null && d.innerA[0] !is d.innerA[1], "could not set array data value");
    d.innerA = [new TestData]; assert(d.innerA.length == 1 && d.innerA[0] !is null, "could not set array data value");
    d.enumerationA ~= TestEnum.Bar; d.enumerationA ~= TestEnum.Foo; assert(d.enumerationA.length == 2 && d.enumerationA[0] == TestEnum.Bar && d.enumerationA[1] == TestEnum.Foo, "could not set array enum value");
    d.enumerationA = [TestEnum.Bar]; assert(d.enumerationA.length == 1 && d.enumerationA[0] == TestEnum.Bar, "could not set array enum value");
    d.additional = "ble"; assert(d.additional == "ble", "could not set second level basic scalar");
    d.nanA ~= double.nan; assert(d.nanA.length == 1 && d.nanA[0] is double.nan, "could not set second level basic scalar");
test.footer(); }

unittest { test.header("data.engine: snap and == of data and member");
    import flow.core.util.templates : as;

    auto d = new InheritedTestData;
    d.uinteger = 5;
    d.text = "foo";
    d.inner = new TestData;
    d.inner.integer = 3;
    d.enumeration = TestEnum.Bar;
    d.uintegerA = [3, 4];
    d.textA = ["foo", "bar"];
    d.innerA = [new TestData, new TestData];
    d.enumerationA = [TestEnum.Bar, TestEnum.Foo];
    d.additional = "ble";

    auto d2 = d.snap().as!InheritedTestData;
    assert(d !is d2, "snaps references are matching");
    assert(d2.uinteger == 5, "could not snap basic scalar value");
    assert(d2.text == "foo", "could not snap basic string value");   
    assert(d2.inner !is null && d2.inner !is d.inner, "could not snap basic data value");
    assert(d2.inner.integer == 3, "could not snap property of basic data value");
    assert(d2.enumeration == TestEnum.Bar, "could not snap basic enum value");
    assert(d2.uintegerA.length == 2 && d2.uintegerA[0] == 3 && d2.uintegerA[1] == 4 && d2.uintegerA !is d.uintegerA, "could not snap array scalar value");
    assert(d2.textA.length == 2 && d2.textA[0] == "foo" && d2.textA[1] == "bar", "could not snap array string value");
    assert(d2.innerA.length == 2 && d2.innerA[0] !is null && d2.innerA[1] !is null && d2.innerA[0] !is d2.innerA[1] && d2.innerA[0] !is d.innerA[0], "could not set array data value");
    assert(d2.enumerationA.length == 2 && d2.enumerationA[0] == TestEnum.Bar && d2.enumerationA[1] == TestEnum.Foo && d2.enumerationA !is d.enumerationA, "could not snap array enum value");

    assert(d2.additional == "ble", "could not snap basic scalar value");

    assert(d == d2, "snaps don't ==");
test.footer(); }

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

unittest { test.header("data.engine: dynamic data usage");
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

struct BinData {
    string[][string] ti;
    ubyte[] data;
}

void bin(T)(T dArr, ref Packer p, ref string[][string] ti)
if(isArray!T && is(ElementType!T:Data)) {
    bin(dArr.length.as!ulong, p, ti);
    foreach(e; dArr)
        bin(e, p, ti);
}

void bin(T)(T d, ref Packer p, ref string[][string] ti)
if(is(T:Data)) {
    if(d !is null) {
        if(d.dataType !in ti)
            foreach(pn; d.properties.keys)
                ti[d.dataType] ~= pn;

        p.pack(d.dataType);
        foreach(pn; ti[d.dataType])
            d.properties[pn].bin(d, p, ti);
    } else p.pack(string.init);
}

void bin(T)(T val, ref Packer p, ref string[][string] ti)
if((isArray!T && !is(ElementType!T:Data)) || (!isArray!T && !is(T:Data))) {
    p.pack(val);
}

/// serializes data to binary
ubyte[] bin(T)(T val)
if(
    canHandle!T || (
        isArray!T &&
        canHandle!(ElementType!T)
    )
) {
    static if(is(T:Data) || (isArray!T && is(ElementType!T:Data))) {
        auto p = Packer();
        string[][string] ti;
        bin!T(val, p, ti);
        BinData bd;
        bd.ti = ti;
        bd.data = p.stream.data;
        return bd.pack;
    } else
        return val.pack;
}

T unbin(T)(ref Unpacker u, ref string[][string] ti)
if(isArray!T && is(ElementType!T:Data)) {
    T dArr;
    auto length = unbin!ulong(u, ti);
    for(auto i = 0; i < length; i++)
        dArr ~= unbin!(ElementType!T)(u, ti);
    return dArr;
}

T unbin(T)(ref Unpacker u, ref string[][string] ti)
if(is(T:Data)) {
    string dataType;
    u.unpack(dataType);
    if(dataType != string.init) {
        auto d = createData(dataType).as!T;
        foreach(pn; ti[dataType])
            d.properties[pn].unbin(d, u, ti);
        return d;
    } else return null;
}

T unbin(T)(ref Unpacker u, ref string[][string] ti)
if((isArray!T && !is(ElementType!T:Data)) || (!isArray!T && !is(T:Data))) {
    T val;
    u.unpack(val);
    return val;
}

/// deserializes binary data
T unbin(T)(ubyte[] arr)
if(
    canHandle!T ||
    (isArray!T && canHandle!(ElementType!T))
) {
    static if(is(T:Data)) {
        auto bd = arr.unpack!BinData;
        auto u = Unpacker(bd.data);
        return unbin!T(u, bd.ti);
    } else
        return arr.unpack!T();
}

unittest { test.header("data.engine: binary serialization of data and member");
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

    auto arr = d.bin;
    //ubyte[] cArr = [255, 0, 0, 0, 0, 0, 0, 0, 27, 102, 108, 111, 119, 46, 100, 97, 116, 97, 46, 73, 110, 104, 101, 114, 105, 116, 101, 100, 84, 101, 115, 116, 68, 97, 116, 97, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 18, 102, 108, 111, 119, 46, 100, 97, 116, 97, 46, 84, 101, 115, 116, 68, 97, 116, 97, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 4, 1, 0, 0, 0, 0, 0, 0, 0, 2, 255, 0, 0, 0, 0, 0, 0, 0, 18, 102, 108, 111, 119, 46, 100, 97, 116, 97, 46, 84, 101, 115, 116, 68, 97, 116, 97, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 18, 102, 108, 111, 119, 46, 100, 97, 116, 97, 46, 84, 101, 115, 116, 68, 97, 116, 97, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 102, 111, 111, 0, 0, 0, 0, 0, 0, 0, 3, 98, 97, 114, 0, 0, 0, 0, 0, 0, 0, 8, 1, 2, 4, 8, 16, 32, 64, 128, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 98, 108, 101, 0, 0, 0, 0, 0, 0, 0, 0, 27, 248, 234, 199, 100, 238, 76, 222, 170, 158, 136, 119, 172, 45, 81, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 102, 111, 111, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    //debug(data) writeln(cArr);
    //debug(data) writeln(arr);
    //assert(arr == cArr, "could not serialize data to bin");
    
    auto tst = arr.unbin!Data;

    auto d2 = arr.unbin!InheritedTestData;
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