include "console.iol"
include "runtime.iol"

include "constants.iol"

include "raftInterface.iol"
include "timerInterface.iol"

include "logger.ol"

type state:void{
    .id: serverId
    .role: string
    .persistent: void{
        /*
            latest term server has seen (init to 0 on first boot)
        */
        .currentTerm: term

        /*
            candidateId that received vote in current term
        */
        .votedFor: serverId
        
        /*
            log entries    
        */
        .log: any
    }

    // volatile state
    .volatile:void{
        /*
            index of highest log entry known to be committed (init to 0)
        */
        .commitIndex: index
        
        /*
            index of highest log entry applied to state machine (init to 0)
        */
        .lastApplied: index
    }

    // // state for the leader reinitialized after election
    // .leader:void{
    //     /*
    //         for each servers, index of next log entry to send to that server
    //     */
    //     .nextIndex[]:index

    //     /*
    //         for each servers, index of highest log entry known to be replicated on server
    //     */
    //     .matchIndex[]: index
    // }
}


// // interfaces
// inputPort myLocalport {
//   Location: LOCAL_LOCATION
//   Interfaces: TimeoutServiceOutputInterface
// }


outputPort internalTimer {
  Interfaces: TimeoutServiceInputInterface
}


inputPort raftInputPort {
    Location: RAFT_LOCATION
    Interfaces: RaftRPCInterface
}

// outputPort raftOutputPort {
//     Protocol: sodep
//     Interfaces: RaftRPCInterface
// }


define embbedTimer{

    with( emb ) {
        .filepath = "-C LOCAL_LOCATION=\"local://server" + global.state.serverId + "\" timerService.ol";
        .type = "Jolie"
    };
    loadEmbeddedService@Runtime( emb )( internalTimer.location )
}

define initVar{

    with(global.state.persistent){
        with(.persistent){
            .currentTerm = 0
        }

        with(.volatile){
            .commitIndex = 0;
            .lastApplied = 0
        }
    }
}


/**
    election procedure do as following
    - increment currentTerm
    - vote for itself
    - reset the election timer
    - send rpc to all other server
    then three possible outcome is following
    if vote received from the majority of servers -> become leader
    if AppendEntry RPC received from new leader -> convert to follower
    if election timeout elasped: start new election
*/
define election{
    scope (election){
        global.state.currentTerm++;
        global.state.votedFor = global.state.serverId;

        // reset timer

        // preparing request
        with(RequestVoteRequest){
            .term = global.state.currentTerm;
            .candidateId = global.state.serverId;
            .lastLogIndex = global.state.lastLogIndex;
            .lastLogTerm = global.state.lastLogTerm
        }
    }
}

define changeToCandidate{
    logEvent@Logger({.serverId = global.state.serverId, .event = "turning to candidate"})()
    synchronized( roleToken ) {
        global.state.role = ROLE_CANDIDATE
    };
    election
}

define changeToFollower{
    logEvent@Logger({.serverId = global.state.serverId, .event = "turning to follower"})()
    synchronized( roleToken ) {
        global.state.role = ROLE_FOLLOWER
    };
    start@internalTimer({.min=1000, .max=2000})(res);
    logEvent@Logger({.serverId = global.state.serverId, .event = "waiting for AppendEntries", .desc.timeout = res.timeout, .desc.id = res.id})()
}

// define changeToLeader{

// }

init{
    global.state.serverId = int(SERVER_ID)
    global.state.serverAmount = int(TOTAL_SERVERS)

    if ( !is_defined(global.state.serverId) || !is_defined(global.state.serverAmount)  ) {
        println@Console("Please, specify server id and server amount")();
        exit
    } else {

        initVar;
        embbedTimer;
        logEvent@Logger({.serverId = global.state.serverId, .event = "server startup"})();
        changeToFollower
    }

}

main{
    [timeoutTicked()()]{
        // current role is follower, should turn to candidate
        if ( global.state.role == ROLE_FOLLOWER){
            changeToCandidate
        } 
        // else if (global.state.role == ROLE_CANDIDATE){

        // };
        log@Logger(global.state)()
    }
    [RequestVote(req)(res){
        logEvent@Logger({.serverId = global.state.serverId, .event = "received request vote rpc", .desc = req})()

    }]
}