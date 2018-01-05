module flow.ctl.app;

import core.stdc.stdlib;
import flow.core;
import flow.ipc.nanomsg;
import flow.service.aspects.process;

void help() {
    import std.stdio;

    writeln("Usage: flowctl command arg1 arg2 ...");
    writeln("Commands:");
    writeln("\tshutdown: request shutdown");

    writeln("\tspace:");
    writeln("\t\tls:");
    writeln("\t\t\tlists spaces and their states");

    writeln("\t\tadd [id] [model]:");
    writeln("\t\t\tadds space from given model using given id");

    writeln("\t\tdel [id]:");
    writeln("\t\t\tremoves space with given id if existing");

    writeln("\t\ttick [id]:");
    writeln("\t\t\tchanges space state to ticking if neccessary");

    writeln("\t\tfreeze [id]:");
    writeln("\t\t\tchanges space state to frozen if neccessary");

    writeln();
    writeln("Example: flowctl space add some.domain.com /usr/share/flow/models/amodel.fjm");

}

Req parse(string[] args){
    import std.range : front, popFront;
    import std.stdio : writeln;

    switch(args.front) {
        case "shutdown":
            return new ShutdownReq;
        case "space":
            args.popFront;
            return args.parse!"space";
        default:
            Log.msg(LL.Error, "I do not understand your request");
            writeln();
            help();
            exit(-1);
    }
    
    return null;
}

Req parse(string cmd)(string[] args) if(cmd == "space") {
    return null;
}

bool checkDomain(string domain) {
    // TODO implement domain validity checks
    return true;
}

void main(string[] args) {
    import core.time : msecs;
    import std.range : popFront;
    import std.uuid : randomUUID;

    Log.level = LL.Debug;

    if(args.length < 2 || args[1] == "-h" || args[1] == "--help") {
        help();
        exit(0);
    }

    args.popFront;
    auto req = args.parse;
    
    auto conn = new NanoMsgConnectorMeta;
    conn.type = fqn!NanoMsgConnector;
    conn.listen = "tcp://*:60110";
    conn.pullListen = "tcp://*:60111";
    conn.pullAddr = "tcp://127.0.0.1:60111";
    conn.wait = 10.msecs;
    conn.retry = 2;
    auto junc = createMeshJunction(randomUUID, "tcp://127.0.0.1:60110", ["tcp://127.0.0.1:60100"], conn);

    if(req !is null)
        request(req, junc);
    else Log.msg(LL.Fatal, "sorry, this shouldn't happen");

    exit(0);
}