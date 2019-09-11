include "console.iol"
include "runtime.iol"

init{
    total_server = 3
      scope (init_servers){
        spawn( i over total_server ) in resultVar {
            println@Console("starting server " + i)();
            with( emb ) {
                .filepath = "-C SERVER_ID=" + i + " "+
                 "-C LOCAL_LOCATION=\"local://server_"+ i + "\" "+
                 "-C RAFT_LOCATION=\"local://server_" + i + "_raft\" "+
                 "-C TOTAL_SERVER=" + total_server + " "+
                 "server.ol";
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