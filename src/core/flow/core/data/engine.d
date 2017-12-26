module flow.core.data.engine;

private import std.variant;
private import std.range;
private import std.traits;
private import flow.core.data.mutex;
private import flow.core.util;

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
        is(T == SysTime) ||
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
    SysTime,
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
	private TypeInfo _info;
    private string _type;
    private string _name;
    private bool _array;
    private TypeDesc _desc;

    private Variant function(Data) _getter;
	private bool function(Data, Variant) _setter;
	private bool function(Data, Data) _equals;
	private void function(Data) _lockReader;
	private void function(Data) _lockWriter;
	private void function(Data) _unlockReader;
	private void function(Data) _unlockWriter;

    /// returns the type informations
    @property TypeInfo info() {return this._info;}

    /// returns the type name
    @property string type() {return this._type;}

    /// returns the name
    @property string name() {return this._name;}

    /// returns if its an array
    @property bool array() {return this._array;}

    /// returns the kind of data
    @property TypeDesc desc() {return this._desc;}

    /// gets the value as variant
    Variant get(Data d) {
        return _getter(d);
    }

    /// sets the value from a variant
    bool set(Data d, Variant v) {
        return _setter(d, v);
    }

    /// checks if it equals for given data objects
    bool equal(Data a, Data b) {
        return _equals(a, b);
    }
}

/// base class of all data
abstract class Data : ILockChildren {
    /// returns all properties of data type
    @property shared(PropertyInfo[string]) properties(){return null;}

    private ReadWriteMutex lock;
    ReadWriteMutex.Reader reader() {return this.lock.reader;}
    ReadWriteMutex.Writer writer() {return this.lock.writer;}

    /// returns data type name
    abstract @property string dataType();

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

        this.lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS, this);
    }

    void readerLockChilds() {
        foreach(pi; this.properties)
            pi.as!PropertyInfo._lockReader(this);
    }

    void writerLockChilds() {
        foreach(pi; this.properties)
            pi.as!PropertyInfo._lockWriter(this);
    }

    void readerUnlockChilds() {
        foreach(pi; this.properties)
            pi.as!PropertyInfo._unlockReader(this);
    }

    void writerUnlockChilds() {
        foreach(pi; this.properties)
            pi.as!PropertyInfo._unlockWriter(this);
    }

    /*override ulong toHash() {
        // TODO collect all hashes of properties and generate collective hash
        return super.toHash;
    }*/

    /// deep clones data object (copies whole memory)
    @property Data clone() {
        import flow.core.util.templates : as;

        Data c = Object.factory(this.dataType).as!Data;

        foreach(prop; this.properties) {
            auto pi = prop.as!PropertyInfo;
            auto val = pi.get(this);
            pi.set(c, val.clone(pi));
        }

        return c;
    }
}

/// mixin allowing to derrive from data
mixin template data() {
    private static import __flowutil = flow.core.util.templates, __flowdata = flow.core.data.engine;
    debug(data) pragma(msg, "\tdata "~__flowutil.fqn!(typeof(this)));

    shared static __flowdata.PropertyInfo[string] Properties;
    override @property shared(__flowdata.PropertyInfo[string]) properties() {
        return Properties;
    }

    override @property string dataType() {return __flowutil.fqn!(typeof(this));}
    
    shared static this() {
		static if(__flowutil.fqn!(typeof(super)) != __flowutil.fqn!Data)
            foreach(n, i; super.Properties)
                Properties[n] = i;
    }

    override @property typeof(this) clone() {
        return cast(typeof(this))super.clone;
    }
}

/// mixin creating a data field
mixin template field(T, string __name)
if (canHandle!T && (!isArray!T || is(T==string))) {
    debug(data) pragma(msg, "\t\t"~T.stringof~" "~__name);

    shared static this() {
        import flow.core.data.engine : Data, PropertyInfo, TPropertyHelper;
        import flow.core.util.templates : as;
        import std.traits : OriginalType;
        import std.variant : Variant;

        mixin("Variant function(Data) getter = (d) {
            auto t = d.as!(typeof(this));
            return Variant("~(is(T : Data) ?
                "t."~__name~".as!Data" :
                "cast("~OriginalType!(T).stringof~")t."~__name)~");
        };");

        mixin("bool function(Data, Variant) setter = (d, v) {
            auto t = d.as!(typeof(this));
            if(v.convertsTo!("~(is(T : Data) ? "Data" : OriginalType!(T).stringof)~")) {
                t."~__name~" = cast("~T.stringof~")"~(is(T : Data) ?
                    "v.get!Data().as!"~T.stringof :
                    "v.get!("~OriginalType!(T).stringof~")")~";
                return true;
            } else return false;
        };");

        mixin("bool function(Data, Data) equals = (a, b) {
            static if(is(T == float) || is(T == double)) {
                import std.math : isIdentical;
                
                return a.as!(typeof(this))."~__name~".isIdentical(b.as!(typeof(this))."~__name~");
            } else
                return a.as!(typeof(this))."~__name~" == b.as!(typeof(this))."~__name~";
        };");

        void function(Data) lockReader = (d) {
            static if(is(T : Data))
                d.reader.lock();
        };

        void function(Data) lockWriter = (d) {
            static if(is(T : Data))
                d.writer.lock();
        };

        void function(Data) unlockReader = (d) {
            static if(is(T : Data))
                d.reader.unlock();
        };

        void function(Data) unlockWriter = (d) {
            static if(is(T : Data))
                d.writer.unlock();
        };

        Properties[__name] = TPropertyHelper!(T, __name).fieldInfo(
            getter,
            setter,
            equals,
            lockReader,
            lockWriter,
            unlockReader,
            unlockWriter
        ).as!(shared(PropertyInfo));
    }

    // field
    mixin(T.stringof~" "~__name~";");
}

import std.range : ElementType;
/// mixin creating a data array
mixin template field(AT, string __name,  T = ElementType!AT)
if(
    isArray!AT &&
    canHandle!(ElementType!AT) &&
    !is(AT == string)
) {
    debug(data) pragma(msg, "\t\t"~AT.stringof~" "~__name);

    shared static this() {
        import flow.core.data.engine : Data, PropertyInfo, TPropertyHelper;
        import flow.core.util.templates : as; 
        import std.traits : OriginalType;
        import std.variant : Variant;

        mixin("Variant function(Data) getter = (d) {
            auto t = d.as!(typeof(this));
            return Variant("~(is(T : Data) ?
                "t."~__name~".as!(Data[])" :
                "cast("~OriginalType!(T).stringof~"[])t."~__name)~");
        };");

        mixin("bool function(Data, Variant) setter = (d, v) {
            auto t = d.as!(typeof(this));
            if(v.convertsTo!("~(is(T : Data) ? "Data" : OriginalType!(T).stringof)~"[])) {
                t."~__name~" = cast("~T.stringof~"[])"~(is(T : Data) ?
                    "v.get!(Data[])().as!("~T.stringof~"[])" :
                    "v.get!("~OriginalType!(T).stringof~"[])")~";
                return true;
            } else return false;
        };");

        mixin("bool function(Data, Data) equals = (a, b) {            
            import std.algorithm.comparison : equal;
            static if(is(T == float) || is(T == double)) {
                import std.math : isIdentical;

                return a.as!(typeof(this))."~__name~
                    ".equal!((x, y) => x.isIdentical(y))(b.as!(typeof(this))."~__name~");
            } else {
                return a.as!(typeof(this))."~__name~".equal(b.as!(typeof(this))."~__name~");
            }
        };");

        void function(Data) lockReader = (a) {
            static if(is(ElementType!T : Data))
                foreach(d; a)
                    d.reader.lock();
        };

        void function(Data) lockWriter = (a) {
            static if(is(ElementType!T : Data))
                foreach(d; a)
                    d.writer.lock();
        };

        void function(Data) unlockReader = (a) {
            static if(is(ElementType!T : Data))
                foreach(d; a)
                    d.reader.unlock();
        };

        void function(Data) unlockWriter = (a) {
            static if(is(ElementType!T : Data))
                foreach(d; a)
                    d.writer.unlock();
        };

        Properties[__name] = TPropertyHelper!(T, __name).arrayInfo(
            getter,
            setter,
            equals,
            lockReader,
            lockWriter,
            unlockReader,
            unlockWriter
        ).as!(shared(PropertyInfo));
    }
    
    // array
    mixin(T.stringof~"[] "~__name~";");
}

/// helper for generating properties
template TPropertyHelper(T, string name) {
    private import std.variant;

    PropertyInfo fieldInfo(
        Variant function(Data) getter,
        bool function(Data, Variant) setter,
        bool function(Data, Data) equals,
        void function(Data) lockReader,
        void function(Data) lockWriter,
        void function(Data) unlockReader,
        void function(Data) unlockWriter
    ) {
        import std.datetime : SysTime, DateTime, Date, Duration;
        import std.traits : OriginalType, isScalarType;
        import std.uuid : UUID;

        PropertyInfo pi;

        static if(isScalarType!T) {
            pi._type = OriginalType!(T).stringof;
            pi._info = typeid(OriginalType!T);
        } else {
            pi._type = T.stringof;
            pi._info = typeid(T);
        }

        pi._name = name;
        pi._array = false;

        pi._getter = getter;
        pi._setter = setter;
        pi._equals = equals;
        pi._lockReader = lockReader;
        pi._lockWriter = lockWriter;
        pi._unlockReader = unlockReader;
        pi._unlockWriter = unlockWriter;

        if(isScalarType!T) pi._desc = TypeDesc.Scalar;
        else if(is(T : Data)) pi._desc = TypeDesc.Data;
        else if(is(T == UUID)) pi._desc = TypeDesc.UUID;
        else if(is(T == SysTime)) pi._desc = TypeDesc.SysTime;
        else if(is(T == DateTime)) pi._desc = TypeDesc.DateTime;
        else if(is(T == Date)) pi._desc = TypeDesc.Date;
        else if(is(T == Duration)) pi._desc = TypeDesc.Duration;
        else if(is(T == string)) pi._desc = TypeDesc.String;

        return pi;
    }

    PropertyInfo arrayInfo(
        Variant function(Data) getter,
        bool function(Data, Variant) setter,
        bool function(Data, Data) equals,
        void function(Data) lockReader,
        void function(Data) lockWriter,
        void function(Data) unlockReader,
        void function(Data) unlockWriter
    ) {
        import std.datetime : SysTime, DateTime, Date, Duration;
        import std.traits : OriginalType, isScalarType;
        import std.uuid : UUID;

        PropertyInfo pi;
        
        static if(isScalarType!T) {
            pi._type = OriginalType!(T).stringof;
            pi._info = typeid(OriginalType!T);
        } else {
            pi._type = T.stringof;
            pi._info = typeid(T);
        }
        
        pi._name = name;
        pi._array = true;

        pi._getter = getter;
        pi._setter = setter;
        pi._equals = equals;
        pi._lockReader = lockReader;
        pi._lockWriter = lockWriter;
        pi._unlockReader = unlockReader;
        pi._unlockWriter = unlockWriter;

        if(isScalarType!T) pi._desc = TypeDesc.Scalar;
        else if(is(T : Data)) pi._desc = TypeDesc.Data;
        else if(is(T == UUID)) pi._desc = TypeDesc.UUID;
        else if(is(T == SysTime)) pi._desc = TypeDesc.SysTime;
        else if(is(T == DateTime)) pi._desc = TypeDesc.DateTime;
        else if(is(T == Date)) pi._desc = TypeDesc.Date;
        else if(is(T == Duration)) pi._desc = TypeDesc.Duration;
        else if(is(T == string)) pi._desc = TypeDesc.String;

        return pi;
    }
}

/// create a data object from its type name
Data createData(string name) {
    import flow.core.util.templates : as;

    return Object.factory(name).as!Data;
}

/// deep clone an array of data
T clone(T)(T arr)
if(
    isArray!T &&
    is(ElementType!T : Data)
) {
    import std.range : ElementType;
    
    T cArr;
    foreach(e; arr) cArr ~= cast(ElementType!T)e.clone;

    return cArr;
}

/// deep clone an array of supported type
T clone(T)(T arr)
if(
    isArray!T &&
    canHandle!(ElementType!T) &&
    !is(ElementType!T : Data)
) {
    T cArr;
    foreach(e; arr) cArr ~= e;

    return cArr;
}

private Variant clone(Variant t, PropertyInfo pi) {
    import std.datetime : SysTime, DateTime, Date, Duration;
    import std.uuid : UUID;
    import std.variant : Variant;

    if(pi.array) {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            return Variant(t.get!(bool[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            return Variant(t.get!(byte[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            return Variant(t.get!(ubyte[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            return Variant(t.get!(short[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            return Variant(t.get!(ushort[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            return Variant(t.get!(int[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            return Variant(t.get!(uint[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            return Variant(t.get!(long[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            return Variant(t.get!(ulong[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            return Variant(t.get!(float[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            return Variant(t.get!(double[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            return Variant(t.get!(char[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            return Variant(t.get!(wchar[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            return Variant(t.get!(dchar[]).clone);
        else if(pi.desc == TypeDesc.UUID)
            return Variant(t.get!(UUID[]).clone);
        else if(pi.desc == TypeDesc.SysTime)
            return Variant(t.get!(SysTime[]).clone);
        else if(pi.desc == TypeDesc.DateTime)
            return Variant(t.get!(DateTime[]).clone);
        else if(pi.desc == TypeDesc.Date)
            return Variant(t.get!(Date[]).clone);
        else if(pi.desc == TypeDesc.Duration)
            return Variant(t.get!(Duration[]).clone);
        else if(pi.desc == TypeDesc.String)
            return Variant(t.get!(string[]).clone);
        else if(pi.desc == TypeDesc.Data)
            return Variant(t.get!(Data[]).clone);
        else assert(false, "this is an impossible situation");
    } else {
        if(pi.desc == TypeDesc.Data) {
            auto d = t.get!(Data);
            return Variant(d !is null ? d.clone : null);
        }
        else return t;
    }
}

version (unittest) enum TestEnum {
    Foo,
    Bar
}

version (unittest) class TestData : Data {
    import std.datetime : SysTime, DateTime, Duration;
    import std.uuid : UUID;

    mixin data;

    // testing basic fields
    mixin field!(TestData, "inner");
    mixin field!(bool, "boolean");
    mixin field!(long, "integer");
    mixin field!(ulong, "uinteger");
    mixin field!(double, "floating");
    mixin field!(TestEnum, "enumeration");
    mixin field!(UUID, "uuid");
    mixin field!(SysTime, "sysTime");
    mixin field!(DateTime, "dateTime");
    mixin field!(Duration, "duration");
    mixin field!(string, "text");

    // testing array fields
    mixin field!(TestData[], "innerA");
    mixin field!(bool[], "booleanA");
    mixin field!(long[], "integerA");
    mixin field!(ulong[], "uintegerA");
    mixin field!(double[], "floatingA");
    mixin field!(TestEnum[], "enumerationA");
    mixin field!(UUID[], "uuidA");
    mixin field!(SysTime[], "sysTimeA");
    mixin field!(DateTime[], "dateTimeA");
    mixin field!(Duration[], "durationA");
    mixin field!(string[], "textA");

    // testing for module name conflicts
    mixin field!(string, "name");
    mixin field!(string, "flow");

    // nan != nan
    mixin field!(double, "nan");
    mixin field!(double[], "nanA");

    // ubyte[] json as base64
    mixin field!(ubyte[], "ubyteA");
}

version(unittest) class InheritedTestData : TestData {
    mixin data;

    mixin field!(string, "additional");
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

unittest { test.header("data.engine: clone and == of data and member");
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

    auto d2 = d.clone().as!InheritedTestData;
 
    assert(d !is d2, "clones references are matching");
    assert(d2.uinteger == 5, "could not clone basic scalar value");
    assert(d2.text == "foo", "could not clone basic string value");   
    assert(d2.inner !is null && d2.inner !is d.inner, "could not clone basic data value");
    assert(d2.inner.integer == 3, "could not clone property of basic data value");
    assert(d2.enumeration == TestEnum.Bar, "could not clone basic enum value");
    assert(d2.uintegerA.length == 2 && d2.uintegerA[0] == 3 && d2.uintegerA[1] == 4 && d2.uintegerA !is d.uintegerA, "could not clone array scalar value");
    assert(d2.textA.length == 2 && d2.textA[0] == "foo" && d2.textA[1] == "bar", "could not clone array string value");
    assert(d2.innerA.length == 2 && d2.innerA[0] !is null && d2.innerA[1] !is null && d2.innerA[0] !is d2.innerA[1] && d2.innerA[0] !is d.innerA[0], "could not set array data value");
    assert(d2.enumerationA.length == 2 && d2.enumerationA[0] == TestEnum.Bar && d2.enumerationA[1] == TestEnum.Foo && d2.enumerationA !is d.enumerationA, "could not clone array enum value");

    assert(d2.additional == "ble", "could not clone basic scalar value");

    assert(d == d2, "clones don't ==");
test.footer(); }