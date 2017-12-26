import std.file, std.path, std.json, std.compiler;

static if(vendor == Vendor.digitalMars) {
    immutable DC = "dmd";
} else static if(vendor == Vendor.llvm) {
    immutable DC = "ldc";
} else static assert(false, "!!! supporting only dmd and ldc yet");

static if(vendor == Vendor.digitalMars) {
    version(Posix) {
        debug {immutable defCflags = ["-debug","-g","-fPIC","-vcolumns","-w","-defaultlib=phobos2"];}
        else {immutable defCflags = ["-fPIC","-w","-defaultlib=phobos2"];}
        immutable defLflags = [];
    }
    version(Windows) {
        debug {immutable defCflags = ["-debug","-g","-fPIC","-vcolumns","-w","-defaultlib=libphobos2.dll"];}
        else {immutable defCflags = ["-w","-defaultlib=libphobos2.dll"];}
        immutable defLflags = ["libphobos2.dll"];
    }
} else static if(vendor == Vendor.llvm) {
    version(Posix) {
        debug {immutable defCflags = ["-d-debug","-g","-vcolumns","-w","-defaultlib=phobos2-ldc"];}
        else {immutable defCflags = ["-w","-defaultlib=phobos2-ldc"];}
        immutable defLflags = [];
    }
    version(Windows) {
        debug {immutable defCflags = ["-d-debug","-g","-vcolumns","-w","-defaultlib=libphobos2-ldc.dll"];}
        else {immutable defCflags = ["-w","-defaultlib=libphobos2.dll"];}
        immutable defLflags = ["libphobos2-ldc.dll"];
    }
}

string rootDir;

T get(T)(JSONValue j, string f, T def = T.init) {
    import std.conv : to;
    import std.range : isArray, ElementType, array;
    import std.algorithm.iteration : map;
    
    if(f in j) {
        static if(isArray!T && !is(T==string))
            return j[f].array.map!(ja => ja.str.to!(ElementType!T)).array;
        else return j[f].str.to!T;
    } else return def;
}

enum LinkType {
    Static,
    Shared,
    Bin
}

abstract class Build {
    version(Posix) {
        immutable staticExt = ".a";
        immutable sharedExt = ".so";
        immutable binExt = string.init;
    }

    version(Windows) {
        immutable staticExt = ".lib";
        immutable sharedExt = ".dll";
        immutable binExt = ".exe";
    }

    string name;
    string main;
    string root;
    string limit;
    string[] deps;
    string[] cflags;
    string[] lflags;
    string[] posixlibs;
    string[] winlibs;

    bool done = false;
    bool clean = false;

    this(string n, string m, string j) {
        this.name = n;
        this.main = m;

        this.load(j);
    }

    final void load(string js) {
        import std.range : empty;

        auto j = parseJSON(js);
        this.root = j.get!string("root");
        this.limit = j.get!string("limit");
        this.deps = j.get!(string[])("deps");
        this.cflags = j.get!(string[])("cflags");
        this.lflags = j.get!(string[])("lflags");
        this.posixlibs = j.get!(string[])("posixlibs");
        this.winlibs = j.get!(string[])("winlibs");
    }

    final bool check(string f) {
        import std.datetime.systime;

        if(!f.exists) return false;

        SysTime tt, ft;
        f.getTimes(tt, ft);

        foreach(s; this.src) {
            SysTime st;
            this.srcRoot.buildPath(s).getTimes(tt, st);

            if(st > ft)
                return false;
        }

        return true;
    }

    final @property string srcRoot() {return this.main.buildPath(this.root);}

    final @property string[] src() {
        import std.range : array;
        import std.algorithm.iteration : map;
        auto limitDir = this.srcRoot.buildPath(this.limit);
        return limitDir.dirEntries("*.d", SpanMode.depth).map!(x => x.relativePath(this.srcRoot)).array;
    }

    final bool checkDeps() {
        foreach(d; this.deps) {
            assert(d in Lib.reg, "!!! dependecy \""~d~"\" of \""~this.name~"\" not found");
            
            if(!Lib.reg[d].clean)
                return false;
        }

        return true;
    }

    final void buildDeps() {
        foreach(d; this.deps) {
            assert(d in Lib.reg, "!!! dependecy \""~d~"\" of \""~this.name~"\" not found");
            
            if(!Lib.reg[d].done)
                Lib.reg[d].doMake();
        }
    }

    version(Posix) final string[] getLibLflags() {
        string[] flags;
        foreach(l; this.posixlibs)
            flags ~= ["-L-l:"~l];
        return flags;
    }
    
    version(Win32) final string[] getLibLflags() {
        string[] flags;
        foreach(l; this.winlibs)
            flags ~= [rootDir.buildPath("dist", "x86", l)];
        return flags;
    }
    
    version(Win64) final string[] getLibLflags() {
        string[] flags;
        foreach(l; this.winlibs)
            flags ~= [rootDir.buildPath("dist", "x86_64", l)];
        return flags;
    }
    
    final void compile(string of, string[] cflags, string[] lflags) {
        import std.conv : to;
        import std.datetime.stopwatch : benchmark;
        import std.range : array;
        import std.stdio : stdin, stdout, stderr, writeln;
        import std.process : spawnProcess, wait, Config;
        // search path for source files

        auto f = {
            auto dcPid = spawnProcess(
                //["echo", DC, "-of"~of]~cflags~lflags~this.src,
                [DC, "-of"~of]~cflags~lflags~this.src,
                stdin, stdout, stderr, null, Config.none, this.srcRoot);
            assert(dcPid.wait() == 0, "!!! compiling error");
        };

        auto b = benchmark!(f)(1);
        writeln("+++ ", b[0]);
    }

    final void run(string exec) {
        import core.time;
        import std.conv : to;
        import std.datetime.stopwatch : benchmark;
        import std.stdio : stdin, stdout, stderr, writeln;
        import std.process : spawnProcess, wait, Config;

        auto f = {
            string[string] env;
            env["LD_LIBRARY_PATH"] = rootDir.buildPath("lib");
            //auto tstPid = spawnProcess(["echo", exec], stdin, stdout, stderr, env, Config.none, rootDir);
            auto tstPid = spawnProcess([exec], stdin, stdout, stderr, env, Config.none, rootDir);
            assert(tstPid.wait() == 0, "!!! execution error");
        };

        auto b = benchmark!(f)(1);
        writeln("--- ", b[0]);
    }
}

final class Lib : Build {
    static Lib[string] reg;

    static void make() {
        foreach(n, l; Lib.reg)
            if(!l.done)
                l.doMake();
    }

    static void test() {
        foreach(n, l; Lib.reg)
            if(!l.tested)
                l.doTest();
    }

    bool tested;

    bool isShared;
    bool genIfc;
    bool shouldTest;
    
    this(string n, string m, bool s, bool i, bool t, string j) {
        super(n, m, j);

        this.isShared = s;
        this.genIfc = i;
        this.shouldTest = t;
    }

    @property string of() {
        return rootDir.buildPath(
            "lib", "lib"~this.name~(this.isShared ? sharedExt : staticExt)
        );
    }

    @property string tof() {
        return rootDir.buildPath(
            "test", "lib", "lib"~this.name~staticExt
        );
    }

    @property string tbof() {
        return rootDir.buildPath(
            "test", this.name~binExt
        );
    }

    final void testDeps() {
        foreach(d; this.deps) {
            assert(d in Lib.reg, "!!! dependecy \""~d~"\" of \""~this.name~"\" not found");
            
            if(!Lib.reg[d].tested)
                Lib.reg[d].doTest();
        }
    }

    string[] getDepCflags() {
        string[] flags;
        foreach(d; this.deps)
            flags ~= Lib.reg[d].getDepCflags();

        if(!this.genIfc)
            flags ~= ["-I"~this.srcRoot];
        return flags;
    }

    version(Posix) string[] getDepLflags(bool test = false) {
        string[] flags;
        foreach(d; this.deps)
            flags ~= Lib.reg[d].getDepLflags(test);

        flags ~= this.getLibLflags();
        if(this.isShared && !test)
            flags ~= ["-L-l:"~this.of.baseName];
        else flags ~= test ? this.tof : this.of;

        return flags;
    }

    version(Windows) string[] getDepLflags(bool test = false) {
        string[] flags;
        foreach(d; this.deps)
            flags ~= Lib.reg[d].getDepLflags();

        // TODO

        return flags;
    }

    string[] getCflags(bool bin = false, bool test = false) {
        string[] flags = cast(string[])defCflags;

        if(this.genIfc)
            flags ~= ["-op", "-Hd="~rootDir.buildPath("ifc")];

        foreach(d; this.deps)
            flags ~= Lib.reg[d].getDepCflags();

        if(bin || test) flags ~= "-unittest";
        if(bin) flags ~= "-main";

        return flags~["-I"~rootDir.buildPath("ifc")];
    }

    string[] getLflags(bool bin = false, bool test = false) {
        string[] flags = cast(string[])defLflags;

        flags ~= this.getLibLflags();

        if(!bin) {
            if(this.isShared && !test) flags ~= "-shared";
            else flags ~= "-lib";
        }

        foreach(d; this.deps)
            flags ~= Lib.reg[d].getDepLflags(test);

        auto libPath = test ? rootDir.buildPath("test", "lib") : rootDir.buildPath("lib");

        return flags~["-L-L"~libPath];
    }
    
    void doMake() {
        import std.stdio : writeln;

        this.buildDeps();

        writeln("*** building \""~this.name~"\"");
        this.clean = this.check(this.of) && this.checkDeps();
        if(!this.clean) {
            this.compile(this.of, this.getCflags(), this.getLflags());
            this.compile(this.tof, this.getCflags(false, true), this.getLflags(false, true));
            if(this.shouldTest)
                this.compile(this.tbof, this.getCflags(true, true), this.getLflags(true, true));
        } else writeln("+++ up to date");

        this.done = true;
    }

    void doTest() {
        import std.stdio : writeln;

        this.testDeps();

        if(this.shouldTest) {
            writeln("*** testing \""~this.name~"\"");
            this.run(this.tbof);
            this.tested = true;
        }
    }
}

final class Bin : Build {
    static Bin[string] reg;

    static void make() {
        foreach(n, b; reg)
            if(!b.done)
                b.doMake();
    }
    
    this(string n, string m, string j) {
        super(n, m, j);
    }

    @property string of() {
        return rootDir.buildPath("bin", "flow-"~this.name~binExt);
    }

    string[] getCflags() {
        string[] flags = cast(string[])defCflags;

        foreach(d; this.deps)
            flags ~= Lib.reg[d].getDepCflags();

        return flags~["-I"~rootDir.buildPath("ifc")];
    }

    string[] getLflags() {
        string[] flags = cast(string[])defLflags;

        flags ~= this.getLibLflags();

        foreach(d; this.deps)
            flags ~= Lib.reg[d].getDepLflags();

        return flags~["-L-L"~rootDir.buildPath("lib")];
    }
    
    void doMake() {
        import std.stdio : writeln;

        this.buildDeps();

        writeln("*** building \""~this.name~"\"");
        this.clean = this.check(this.of) && this.checkDeps();
        if(!this.clean) {
            this.compile(of, this.getCflags(), this.getLflags());
        } else writeln("+++ up to date");

        this.done = true;
    }
}

void loadLibs() {
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("*.lib.json", SpanMode.depth);
    foreach(j; jsons) {
        auto name = j.baseName(".lib.json");
        writeln("*** adding library ", name);
        Lib.reg[name] = new Lib(name, j.dirName.buildPath(name), false, false, false, j.readText);
    }
}

void loadCore() {
    import std.range : front, empty, array;
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("core.json", SpanMode.depth).array;
    if(!jsons.empty) {
        if(jsons.length > 1) assert("!!! there cannot be multiple core definitions");
        auto j = jsons.front;
        auto name = "core";
        writeln("*** adding flow core");
        Lib.reg[name] = new Lib(name, j.dirName.buildPath(name), true, true, true, j.readText);
    }
}

void loadExts() {
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("*.ext.json", SpanMode.depth);
    foreach(j; jsons) {
        auto name = j.baseName(".ext.json");
        writeln("*** adding extension ", name);
        Lib.reg[name] = new Lib(name, j.dirName.buildPath(name), true, true, true, j.readText);
    }
}

void loadBins() {
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("*.bin.json", SpanMode.depth);
    foreach(j; jsons) {
        auto name = j.baseName(".bin.json");
        writeln("*** adding binary ", name);
        Bin.reg[name] = new Bin(name, j.dirName.buildPath(name), j.readText);
    }
}

void loadDocs() {
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("*.doc.json", SpanMode.depth);
    foreach(j; jsons) {
        auto name = j.baseName(".doc.json");
        writeln("*** adding doc ", name);
        Bin.reg[name] = new Bin(name, j.dirName.buildPath(name), j.readText);
    }
}

int main(string[] args) {
    import std.stdio : writeln;

    writeln("*** compiling using "~DC);

    rootDir = getcwd;

    auto cmd = args.length > 1 ? args[1] : "build";

    if(cmd == "rebuild" || cmd == "clean") {
        if(rootDir.buildPath("ifc").exists)
            rootDir.buildPath("ifc").rmdirRecurse;

        if(rootDir.buildPath("lib").exists)
            rootDir.buildPath("lib").rmdirRecurse;

        if(rootDir.buildPath("bin").exists)
            rootDir.buildPath("bin").rmdirRecurse;

        if(rootDir.buildPath("test").exists)
            rootDir.buildPath("test").rmdirRecurse;
    }

    if(cmd == "build" || cmd == "rebuild") {
        rootDir.buildPath("ifc").mkdirRecurse;
        rootDir.buildPath("lib").mkdirRecurse;
        rootDir.buildPath("bin").mkdirRecurse;
        rootDir.buildPath("test").mkdirRecurse;
        rootDir.buildPath("test", "lib").mkdirRecurse;

        loadLibs();
        loadCore();
        loadExts();
        loadBins();
        loadDocs();
        
        Lib.make();
        Lib.test();
        Bin.make();
    }

    return 0;
}