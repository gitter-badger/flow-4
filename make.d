import core.stdc.stdlib;
import std.compiler;
import std.json;

/* CMAKE WINDOWS HACKS
set(CompilerFlags
        CMAKE_CXX_FLAGS
        CMAKE_CXX_FLAGS_DEBUG
        CMAKE_CXX_FLAGS_RELEASE
        CMAKE_C_FLAGS
        CMAKE_C_FLAGS_DEBUG
        CMAKE_C_FLAGS_RELEASE
        )
foreach(CompilerFlag ${CompilerFlags})
  string(REPLACE "/MD" "/MT" ${CompilerFlag} "${${CompilerFlag}}")
endforeach()
*/

version(X86) static assert(false, "32 bit targets are not suported");

static if(vendor == Vendor.digitalMars) {
    version(Posix) immutable DC = "dmd";
    version(Windows) immutable DC = "dmd.exe";
} else static if(vendor == Vendor.llvm) {
    version(Posix) immutable DC = "ldc";
    version(Windows) 
        static assert(false, "!!! supporting only dmd -m64 or -m32mscoff on windows yet");
} else static assert(false, "!!! supporting only dmd and ldc yet");

static if(vendor == Vendor.digitalMars) {
    version(Posix) {
        debug {
            version(X86_64) immutable defCflags = [/*"-debug=data", */"-debug","-g", "-m64","-fPIC","-vcolumns","-w"];
            immutable defLflags = [];
        }
        else {
            version(X86_64) immutable defCflags = ["-m64","-fPIC","-w"];
            immutable defLflags = [];
        }
    }
    version(Windows) {
        debug {
            version(X86_64) immutable defCflags = ["-debug","-g","-m64","-vcolumns","-w"];
            immutable defLflags = [/*"-L/NODEFAULTLIB:MSVCRTD"*/];
        }
        else {
            version(X86_64) immutable defCflags = ["-m64","-w"];
            immutable defLflags = [/*"-L/NODEFAULTLIB:MSVCRT""*/];
        }
    }
} else static if(vendor == Vendor.llvm) {
    version(Posix) {
        debug {
            version(X86_64) immutable defCflags = [/*"-d-debug=data", */"-d-debug","-g", "-m64","-fPIC","-vcolumns","-w","-defaultlib=phobos2-ldc"];
            immutable defLflags = [];
        }
        else {
            version(X86_64) immutable defCflags = ["-m64","-fPIC","-w","-defaultlib=phobos2-ldc"];
            immutable defLflags = [];
        }
    }
    version(Windows) {
        /*debug {immutable defCflags = ["-d-debug","-g","-vcolumns","-w","-defaultlib=libphobos2-ldc.dll"];}
        else {immutable defCflags = ["-w","-defaultlib=phobos2-ldc"];}
        immutable defLflags = ["libphobos2-ldc.dll"];*/
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

    this(string n, string m, string js) {
        this.name = n;
        this.main = m;

        this.load(js);
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
        import std.datetime.systime : SysTime;
        import std.file : getTimes;
        import std.path : buildPath, exists;

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

    final @property string srcRoot() {
        import std.path : buildPath;
        return this.main.buildPath(this.root);
    }

    final @property string[] src() {
        import std.algorithm.iteration : map;
        import std.file : dirEntries, SpanMode;
        import std.path : buildPath, relativePath;
        import std.range : array;

        auto limitDir = this.srcRoot.buildPath(this.limit);
        return limitDir.dirEntries("*.d", SpanMode.depth).map!(x => x.relativePath(this.srcRoot)).array;
    }

    final bool checkDeps() {
        foreach(d; this.deps) {
            assert(d in Lib.reg, "!!! dependency \""~d~"\" of \""~this.name~"\" not found");
            
            if(!Lib.reg[d].clean)
                return false;
        }

        return true;
    }

    final void buildDeps() {
        foreach(d; this.deps) {
            assert(d in Lib.reg, "!!! dependency \""~d~"\" of \""~this.name~"\" not found");
            
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
    
    version(Windows) final string[] getLibLflags() {
        string[] flags;
        foreach(l; this.winlibs)
            flags ~= ["-L"~l];
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
                [DC, "-of"~of]~cflags~lflags~this.src,
                stdin, stdout, stderr, null, Config.none, this.srcRoot);
            if(dcPid.wait() != 0) {
                writeln("!!! compiling error at");
                spawnProcess(
                ["echo", DC, "-of"~of]~cflags~lflags~this.src,
                stdin, stdout, stderr, null, Config.none, this.srcRoot);
                exit(-1);
            }
        };

        auto b = benchmark!(f)(1);
        writeln("+++ ", b[0]);
    }

    final void run(string exec) {
        import core.time;
        import std.conv : to;
        import std.datetime.stopwatch : benchmark;
        import std.stdio : stdin, stdout, stderr, writeln;
        import std.path : buildPath;
        import std.process : spawnProcess, wait, Config;

        auto f = {
            string[string] env;
            env["LD_LIBRARY_PATH"] = rootDir.buildPath("lib");
            auto tstPid = spawnProcess([exec], stdin, stdout, stderr, env, Config.none, rootDir);
            if(tstPid.wait() != 0) {
                writeln("!!! execution error");
                exit(-1);
            }
        };

        auto b = benchmark!(f)(1);
        writeln("--- ", b[0]);
    }
}

final class Lib : Build {
    static Lib[string] reg;

    static void make() {
        foreach(n, l; Lib.reg)
            if(!l.done && l.obligate)
                l.doMake();
    }

    bool obligate;
    bool isShared;
    bool genIfc;
    bool shouldTest;

    // not actually implemented
    string[][] custMake;
    string[][] custTest;
    
    this(string n, string m, bool s, bool o, bool i, bool t, string js) {
        super(n, m, js);

        this.obligate = o;
        version(Posix) this.isShared = s;
        this.genIfc = i;
        this.shouldTest = t;

        auto j = parseJSON(js);
        this.custMake = j.get!(string[][])("make");
        this.custTest = j.get!(string[][])("test");
    }

    @property string of() {
        import std.path : buildPath;

        return rootDir.buildPath(
            "lib", "lib"~this.name~(this.isShared ? sharedExt : staticExt)
        );
    }

    @property string tof() {
        import std.path : buildPath;

        return rootDir.buildPath(
            "test", "lib", "lib"~this.name~staticExt
        );
    }

    @property string tbof() {
        import std.path : buildPath;

        return rootDir.buildPath(
            "test", this.name~binExt
        );
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
        import std.path : baseName;

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
        import std.path : baseName;

        string[] flags;
        foreach(d; this.deps)
            flags ~= Lib.reg[d].getDepLflags();

        flags ~= this.getLibLflags();
        if(this.isShared && !test)
            flags ~= ["-L"~this.of.baseName];
        else flags ~= test ? this.tof : this.of;

        return flags;
    }

    string[] getCflags(bool bin = false, bool test = false) {
        import std.path : buildPath;

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
        import std.path : buildPath;

        string[] flags = cast(string[])defLflags;

        flags ~= this.getLibLflags();

        if(!bin) {
            if(this.isShared && !test) flags ~= "-shared";
            else flags ~= "-lib";
        }

        foreach(d; this.deps)
            flags ~= Lib.reg[d].getDepLflags(test);

        auto libPath = test ? rootDir.buildPath("test", "lib") : rootDir.buildPath("lib");
        version(Posix) flags ~= ["-L-L"~libPath];
        version(Windows) {
            flags ~= [
                "-L/LIBPATH:"~libPath];//,
                //"-L/PDB:"~(test ? this.tof : this.of).baseName~".pdb"];

            debug {
                version(X86_64)
                    flags ~= ["-L/LIBPATH:"~rootDir.buildPath("dist", "x86_64", "debug")];
            } else {
                version(X86_64)
                    flags ~= ["-L/LIBPATH:"~rootDir.buildPath("dist", "x86_64", "release")];
            }
        }

        return flags;
    }
    
    void doMake() {
        import std.stdio : writeln;

        this.buildDeps();

        this.clean = this.check(this.of) && this.checkDeps();
        
        if(!this.clean) {
            this.test();

            writeln("*** building \""~this.name~"\"");
            this.compile(this.of, this.getCflags(), this.getLflags());
            this.compile(this.tof, this.getCflags(false, true), this.getLflags(false, true));
        } else writeln("*** up to date \""~this.name~"\"");

        this.done = true;
    }

    void test() {
        import std.stdio : writeln;

        if(this.shouldTest) {
            writeln("*** testing \""~this.name~"\"");
            this.compile(this.tbof, this.getCflags(true, true), this.getLflags(true, true));

            this.run(this.tbof);
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

    string _of;
    
    this(string n, string m, string js) {
        super(n, m, js);

        auto j = parseJSON(js);
        this._of = j.get!(string)("of");
    }

    @property string of() {
        import std.path : buildPath;

        return rootDir.buildPath("bin", this._of == string.init ? "flow-"~this.name~binExt : this._of);
    }

    string[] getCflags() {
        import std.path : buildPath;
        
        string[] flags = cast(string[])defCflags;

        foreach(d; this.deps)
            flags ~= Lib.reg[d].getDepCflags();

        return flags~["-I"~rootDir.buildPath("ifc")];
    }

    string[] getLflags() {
        import std.path : buildPath;

        string[] flags = cast(string[])defLflags;

        flags ~= this.getLibLflags();

        foreach(d; this.deps)
            flags ~= Lib.reg[d].getDepLflags();

        auto libPath = rootDir.buildPath("lib");
        version(Posix) flags ~= ["-L-L"~libPath];
        version(Windows) {
            flags ~= [
                "-L/LIBPATH:"~libPath];//,
                //"-L/PDB:"~(test ? this.tof : this.of).baseName~".pdb"];

            debug {
                version(X86_64)
                    flags ~= ["-L/LIBPATH:"~rootDir.buildPath("dist", "x86_64", "debug")];
            } else {
                version(X86_64)
                    flags ~= ["-L/LIBPATH:"~rootDir.buildPath("dist", "x86_64", "release")];
            }
        }

        return flags;
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
    import std.file : dirEntries, SpanMode, readText;
    import std.path : buildPath, baseName, dirName;
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("*.lib.json", SpanMode.depth);
    foreach(j; jsons) {
        auto name = j.baseName(".lib.json");
        writeln("::: adding library ", name);
        Lib.reg[name] = new Lib(name, j.dirName.buildPath(name), false, false, false, false, j.readText);
    }
}

void loadCore() {
    import std.file : dirEntries, SpanMode, readText;
    import std.path : buildPath, baseName, dirName;
    import std.range : front, empty, array;
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("core.json", SpanMode.depth).array;
    if(!jsons.empty) {
        if(jsons.length > 1) assert("!!! there cannot be multiple core definitions");
        auto j = jsons.front;
        auto name = "core";
        writeln("::: adding flow core");
        Lib.reg[name] = new Lib(name, j.dirName.buildPath(name), true, true, true, true, j.readText);
    }
}

void loadExts() {
    import std.file : dirEntries, SpanMode, readText;
    import std.path : buildPath, baseName, dirName;
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("*.ext.json", SpanMode.depth);
    foreach(j; jsons) {
        auto name = j.baseName(".ext.json");
        writeln("::: adding extension ", name);
        Lib.reg[name] = new Lib(name, j.dirName.buildPath(name), true, true, true, true, j.readText);
    }
}

void loadBins() {
    import std.file : dirEntries, SpanMode, readText;
    import std.path : buildPath, baseName, dirName;
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("*.bin.json", SpanMode.depth);
    foreach(j; jsons) {
        auto name = j.baseName(".bin.json");
        writeln("::: adding binary ", name);
        Bin.reg[name] = new Bin(name, j.dirName.buildPath(name), j.readText);
    }
}

void loadDocs() {
    import std.file : dirEntries, SpanMode, readText;
    import std.path : buildPath, baseName, dirName;
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("*.doc.json", SpanMode.depth);
    foreach(j; jsons) {
        auto name = j.baseName(".doc.json");
        writeln("::: adding doc ", name);
        Bin.reg[name] = new Bin(name, j.dirName.buildPath(name), j.readText);
    }
}

void clean() {
    import std.file : rmdirRecurse, exists;
    import std.path : buildPath;
    import std.stdio : writeln;

    writeln("*** cleaning up");
    if(rootDir.buildPath("ifc").exists)
        rootDir.buildPath("ifc").rmdirRecurse;

    if(rootDir.buildPath("lib").exists)
        rootDir.buildPath("lib").rmdirRecurse;

    if(rootDir.buildPath("bin").exists)
        rootDir.buildPath("bin").rmdirRecurse;

    if(rootDir.buildPath("test").exists)
        rootDir.buildPath("test").rmdirRecurse;
}

void build() {
    import std.file : mkdirRecurse;
    import std.path : buildPath, exists;
    import std.stdio : writeln;

    writeln("*** loading packages");
    loadLibs();
    loadCore();
    loadExts();
    loadBins();
    loadDocs();

    writeln("*** compiling using "~DC);
    rootDir.buildPath("ifc").mkdirRecurse;
    rootDir.buildPath("lib").mkdirRecurse;
    rootDir.buildPath("bin").mkdirRecurse;
    rootDir.buildPath("test").mkdirRecurse;
    rootDir.buildPath("test", "lib").mkdirRecurse;
    
    Lib.make();
    Bin.make();
}

version(Posix) void install() {
    import std.file : copy, exists, remove, Yes;
    import std.path : buildPath, baseName;
    import std.process : environment;
    import std.stdio : writeln;

    auto user = environment["USER"];
    
    if(user != "root") {
        writeln("!!! cannot install without beeing root");
        exit(-1);
    }

    writeln("*** loading packages");
    loadLibs();
    loadCore();
    loadExts();
    loadBins();

    auto systemLibPath = "/".buildPath("usr", "lib");
    auto systemBinPath = "/".buildPath("usr", "bin");

    writeln("*** installing libraries");
    foreach(n, l; Lib.reg)
        if(l.isShared) {
            auto t = systemLibPath.buildPath(l.of.baseName);
            writeln("::: ", l.of, " >>> ", t);
            if(t.exists) t.remove();
            l.of.copy(t, Yes.preserveAttributes);
        }

    writeln("*** installing binaries");
    foreach(n, b; Bin.reg) {
        auto t = systemBinPath.buildPath(b.of.baseName);
        writeln("::: ", b.of, " >>> ", t);
        if(t.exists) t.remove();
        b.of.copy(t, Yes.preserveAttributes);
    }
}

version(Posix) void uninstall() {
    import std.file : remove, exists;
    import std.path : buildPath, baseName;
    import std.process : environment;
    import std.stdio : writeln;

    auto user = environment["USER"];
    
    if(user != "root") {
        writeln("!!! cannot uninstall without beeing root");
        exit(-1);
    }

    writeln("*** loading packages");
    loadLibs();
    loadCore();
    loadExts();
    loadBins();

    auto systemLibPath = "/".buildPath("usr", "lib");
    auto systemBinPath = "/".buildPath("usr", "bin");

    writeln("*** uninstalling libraries");
    foreach(n, l; Lib.reg)
        if(l.isShared) {
            auto f = systemLibPath.buildPath(l.of.baseName);
            if(f.exists) {
                writeln("::: removing ", f);
                f.remove();
            }
        }

    writeln("*** uninstalling binaries");
    foreach(n, b; Bin.reg) {
        auto f = systemBinPath.buildPath(b.of.baseName);
        if(f.exists) {
            writeln("::: removing ", f);
            f.remove();
        }
    }
}

version(Windows) void install() {
    import std.c.stdlib : getenv;
}

version(Windows) void uninstall() {
    import std.c.stdlib : getenv;
}

void main(string[] args) {
    import std.path : getcwd;
    import std.stdio : writeln;

    rootDir = getcwd;

    auto cmd = args.length > 1 ? args[1] : "build";
    switch(cmd) {
        case "build":
            build();
            break;
        case "rebuild":
            clean();
            build();
            break;
        case "clean":
            clean();
            break;
        case "install":
            install();
            break;
        case "uninstall":
            uninstall();
            break;
        default:
            writeln("!!! argument \"", cmd, "\" unknown");
            exit(-1);
    }

    exit(0);
}