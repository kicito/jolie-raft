include "console.iol"
include "runtime.iol"

include "constants.iol"

include "raftInterface.iol"
include "timerInterface.iol"

include "logger.ol"



// interfaces
inputPort myLocalport {
  Location: LOCAL_PORT
  Interfaces: TimeoutServiceOutputInterface, RaftRPCInterface
}


outputPort internalTimer {
  Interfaces: TimeoutServiceInputInterface
}


inputPort raftInputPort {
    Location: RAFT_PORT
    Interfaces: RaftRPCInterface
}

outputPort raftOutputPort {
    Interfaces: RaftRPCInterface
}


type state:void{
    .id: serverId
    .role: string | void
    .persistent: void{
        /*
            latest term server has seen (init to 0 on first boot)
        */
        .currentTerm: term

        /*
            candidateId that received vote in current term
        */
        .votedFor: serverId | void
        
        /*
            log entries    
        */
        .logs: void{
            .term: term
            .entry: any
        }
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

type serverLogType: void{
  state: state
  desc?: anyType 
}



define embbedTimer{

    with( emb ) {
        .filepath = "-C LOCAL_LOCATION=\"local://server" + global.state.serverId + "\" timerService.ol";
        .type = "Jolie"
    };
    loadEmbeddedService@Runtime( emb )( internalTimer.location )
}

define initVar{
    scope (initVar){
        with(global.state){
            with(.persistent){
                .currentTerm = 0
                .votedFor = void
            }
            with(.volatile){
                .commitIndex = 0;
                .lastApplied = 0
            }
        }
    }
}



define broadcastRequestVoteRPC{
    // send request to every server, expected requestVoteRequest is set from election procedure
    logEvent@Logger({.serverId = global.state.serverId, .event="broadcast RequestVoteRPC", .desc = requestVoteRequest})()
    for( i = 0, i < global.state.serverAmount, i++ ) {
        if ( i != global.state.serverId){
            stringReplaceReq = LOCAL_PORT;
            stringReplaceReq.regex = string(global.state.serverId);
            stringReplaceReq.replacement = "" + i;
            replaceFirst@StringUtils( stringReplaceReq )( destinationLocation );
            logEvent@Logger({.serverId = global.state.serverId, .event="sending request to port " + destinationLocation})();
            raftOutputPort.location = destinationLocation
            requestVote@raftOutputPort(requestVoteRequest)
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
        logEvent@Logger({.serverId = global.state.serverId, .event="attempt to start new election"})()
        global.state.persistent.currentTerm++;
        global.state.persistent.votedFor = global.state.serverId;

        // reset timer
        
        // preparing request
        requestVoteRequest = global.state.serverId;
        with(requestVoteRequest){
            .term = global.state.persistent.currentTerm;
            .candidateId = global.state.serverId;
            .lastLogIndex = #global.state.persistent.logs;
            if (is_defined(global.state.persistent.logs[#global.state.persistent.logs].term)){
                .lastLogTerm = global.state.persistent.logs[#global.state.persistent.logs].term
            }else{
                .lastLogTerm = 0
            }
        };
        broadcastRequestVoteRPC
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
        logEvent@Logger({.serverId = global.state.serverId, .event="totalServer = " + global.state.serverAmount})();
        initVar;
        embbedTimer;
        logEvent@Logger({.serverId = global.state.serverId, .event = "server startup"})();
        changeToFollower
    }

}

main{
    [timeoutTicked()()]{
        logEvent@Logger({.serverId = global.state.serverId, .event = "timeout Ticked"})()
        // current role is follower, turn to candidate
        if ( global.state.role == ROLE_FOLLOWER){
            changeToCandidate
        } 
        // else if (global.state.role == ROLE_CANDIDATE){

        // };
    }
    [requestVote(req)]{
        logEvent@Logger({.serverId = global.state.serverId, .event = "receive requestVote RPC"})()
        logVar@Logger(req)()
    }
}