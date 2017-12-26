module flow.core.util.log;

enum LL {
    Message = 0,
    Fatal = 1,
    Error = 2,
    Warning = 3,
    Info = 4,
    Debug = 5,
    FDebug = 6
}

/// flow system logger
final class Log {
    private import flow.core.data.engine : Data;
    private import std.ascii : newline;
    private import std.range : isArray;

    /// separation string 
    public static immutable sep = newline~"--------------------------------------------------"~newline;

    /// chosen log level
    public shared static LL logLevel = LL.Warning;

    private static string get(Throwable thr) {
        import flow.core.data.json : json;
        import flow.core.util.error : FlowException;
        import flow.core.util.templates : as;
        import std.conv : to;
        
        string str;

        if(thr !is null) {
            str ~= sep~thr.file~":"~thr.line.to!string;

            if(thr.msg != string.init)
                str ~= "("~thr.msg~newline~")";

            str ~= newline~thr.info.to!string;
        }

        if(thr.as!FlowException !is null && thr.as!FlowException.data !is null) {
            str ~= sep;
            str ~= thr.as!FlowException.data.json(true)~newline;
            str ~= sep;
            str ~= sep;
        }

        return str;
    }

    private static string get(Data d) {
        import flow.core.data.json : json;

        return d !is null ? Log.sep~d.json(true) : string.init;
    }

    /// log a message
    public static void msg(LL level, string msg) {
        import flow.core.util.templates : as;
        Log.msg(level, msg, null, null.as!Data);
    }

    /// log a message coming with an error or exception
    public static void msg(LL level, string msg, Throwable thr) {
        import flow.core.util.templates : as;
        Log.msg(level, msg, thr, null.as!Data);
    }
    
    /// log a message coming with context data
    public static void msg(DT)(LL level, string msg, DT dIn) if(is(DT : Data) || (isArray!DT && is(ElementType!DT:Data))) {
        Log.msg(level, msg, null, dIn);
    }

    /// log an error or exception
    public static void msg(LL level, Throwable thr) {
        import flow.core.util.templates : as;

        Log.msg(level, string.init, thr, null.as!Data);
    }

    /// log an error or exception coming with context data
    public static void msg(DT)(LL level, Throwable thr, DT dIn) if(is(DT : Data) || (isArray!DT && is(ElementType!DT:Data))) {
        Log.msg(level, string.init, thr, dIn);
    }

    /// log a data object
    public static void msg(DT)(LL level, DT dIn) if(is(DT : Data) || (isArray!DT && is(ElementType!DT:Data))) {
        Log.msg(level, string.init, null, dIn);
    }

    /// log a message coming with an error or exception and context data
    public static void msg(DT)(LL level, string msg, Throwable thr, DT dIn) if(is(DT : Data) || (isArray!DT && is(ElementType!DT:Data))) {
        import std.traits : isArray;

        if(level <= logLevel) {
            string str = msg;
            str ~= Log.get(thr);
            static if(isArray!DT) {
                foreach(d; dIn)
                    str ~= Log.get(d);
            } else str ~= Log.get(dIn);
            Log.print(level, str);
        }
    }

    private static void print(LL level, string msg) {
        import std.conv : to;
        import std.stdio : writeln;

        if(level <= logLevel) {
            auto str = "["~level.to!string~"] ";
            str ~= msg;

            synchronized {
                writeln(str);
                //flush();
            }
        }
    }
}