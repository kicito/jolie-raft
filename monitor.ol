include "console.iol"
include "runtime.iol"
include "raftClientInterface.iol"
include "string_utils.iol"

outputPort clientPort{
    Protocol: http
    Interfaces: ClientRaftRPCInterface
}

init{
    global.total_server = TOTAL_SERVERS
    // scope (init_servers){
    //     spawn( i over total_server ) in resultVar {
    //         argrument = "-C SERVER_ID=" + i + " " +
    //                 "-C LOCAL_PORT=\"socket://localhost:800"+ i + "\" " +
    //                 "-C CLIENT_PORT=\"socket://localhost:900" + i + "/\" " +
    //                 "-C RAFT_PORT=\"socket://localhost:1000" + i + "\" "+
    //                 "-C TOTAL_SERVERS=" + total_server + " " +
    //                 "server.ol";
    //         println@Console("starting server " + i + " with jolie " + argrument)();
    //         with( emb ) {
    //             .filepath = argrument;
    //             .type = "Jolie"
    //         };
            
    //         loadEmbeddedService@Runtime( emb )( p )
    //         global.serverLocation[i] = "socket://localhost:900" + i + "/"
    //     }
    // };


    for ( i = 0, i < global.total_server, i++){
        global.serverLocation[i] = "socket://localhost:900" + i + "/"
        println@Console( "[main] registering server " + global.serverLocation[i])(  )
    }
    registerForInput@Console()()
    println@Console( "[main] Monitor is ready" )(  )
}

main{
    while( cmd != "exit" ) {
        in( cmd )
        splitCmd = cmd
        splitCmd.regex = "\\s"
        split@StringUtils( splitCmd )( splitedCmd );
        if (splitedCmd.result[0] == "send"){
            if (#splitedCmd.result != 3){
                println@Console( "[main] invalid command " + splitedCmd.result[0] + " arguments, expected 3 but received " + #splitedCmd.result )(  )
            } else {
                println@Console( "[main] invoke clientRequest@" + global.serverLocation[splitedCmd.result[1]] + " with value " + splitedCmd.result[2] )(  )
                clientPort.location = global.serverLocation[splitedCmd.result[1]];
                with(clientRequest){
                    .value = splitedCmd.result[2]
                };
                add@clientPort(clientRequest)(res);
                println@Console("result = " + res.success + ", message = " + res.message)()
            }
        }else{
            println@Console( "[main] invalid command " + splitedCmd.result[0] )(  )
        }

    }
}