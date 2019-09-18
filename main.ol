include "console.iol"
include "runtime.iol"

init{
    total_server = 3
    scope (init_servers){
        spawn( i over total_server ) in resultVar {
            argrument = "-C SERVER_ID=" + i + " " +
                    "-C LOCAL_PORT=\"local://server-"+ i + "\" "+
                    "-C RAFT_PORT=\"local://server-" + i + "-raft\" "+
                    "-C TOTAL_SERVERS=" + total_server + " " +
                    "server.ol";
            println@Console("starting server " + i + " with jolie " + argrument)();
            with( emb ) {
                .filepath = argrument;
                .type = "Jolie"
            };
            
            loadEmbeddedService@Runtime( emb )( p )
        }
    };
    registerForInput@Console()()
}

main{
    while( cmd != "exit" ) {
        in( cmd )
    }
}