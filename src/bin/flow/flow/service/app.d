module flow.serivce.app;

import core.stdc.stdlib;
import flow.core;
import flow.ipc.nanomsg;
import flow.service.aspects.process;

bool stopped;
string path;
Process proc;

extern (C) void stop(int signal) {
    if(!stopped) {
        shutdown();
        stopped = true;
    } else {
        Log.msg(LL.Fatal, "force exiting");
        unlock();
        exit(-1);
    }
}

version(Posix) {
    extern (C) void die(int signal) {
        Log.msg(LL.Fatal, "Memory access error (SIGSEGV) occured -> exiting");
        unlock();
        exit(-999);
    }
}

void lock() {
    import flow.core.util : Log;
    import std.path : buildPath;
    import std.file : write, exists;
    import std.stdio : writeln;

    auto f = path.buildPath("flow.lck");
    if(f.exists) {
        Log.msg(LL.Error, "lockfile \""~path~"\" already exists, is any instance on this target path running? You may remove it by hand if you are sure.");
        exit(-2);
    } else
        f.write(path);        
}

void unlock() {
    import flow.core.util : Log;
    import std.path : buildPath;
    import std.file : remove, exists;
    import std.stdio : writeln;    

    auto f = path.buildPath("flow.lck");
    if(f.exists)
        f.remove();
}

void main(string[] args) {
    import core.time : msecs;
    import std.file : exists, mkdirRecurse;
    import std.path : buildPath;
    import std.stdio : writeln;
    import std.uuid : randomUUID;

    Log.level = LL.Debug;

    version(Posix) { // posix supports catching ctrl+c and SIGSEGV
        static import core.sys.posix.signal;
        core.sys.posix.signal.sigset(core.sys.posix.signal.SIGINT, &stop);

        static import core.stdc.signal, core.sys.posix.signal;
        core.sys.posix.signal.sigset(core.stdc.signal.SIGSEGV, &die);
    }

    // setting path
    version(Posix) {
        path = "/".buildPath("var", "lib", "flow");
    }
    version(Windows) {
        import std.c.stdlib : getenv;
        path = getenv("PROGRAMDATA").to!string.buildPath("flow");
    }

    if(!path.exists)
        path.mkdirRecurse;

    // setting junction
    auto conn = new NanoMsgConnectorMeta;
    conn.type = fqn!NanoMsgConnector;
    conn.listen = "tcp://*:60100";
    conn.pullListen = "tcp://*:60101";
    conn.pullAddr = "tcp://127.0.0.1:60101";
    conn.wait = 10.msecs;
    conn.retry = 2;
    auto junc = createMeshJunction(randomUUID, "tcp://127.0.0.1:60100", [], conn);
    lock();

    auto cfg = new ProcessConfig;
    cfg.fsroot = path;
    proc = new Process(cfg);

    control(proc, [junc]);

    proc.dispose();
    unlock();
    
    exit(0);
}