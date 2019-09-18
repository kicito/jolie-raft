include "console.iol"
include "runtime.iol"

include "constants.iol"

include "raftInterface.iol"

include "logger.ol"

include "timerInterface.iol"


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
            .broadcastTime = 2000;
            with(.persistent){
                .currentTerm = 0
                .votedFor = undefined
            }
            with(.volatile){
                .commitIndex = 0;
                .lastApplied = 0
            }
            global.state.candidate.grantCount =0      
        }
        for ( i = 0, i < global.state.serverAmount, i++){
            if ( i != global.state.serverId){
                stringReplaceReq = LOCAL_PORT;
                stringReplaceReq.regex = string(global.state.serverId);
                stringReplaceReq.replacement = "" + i;
                replaceFirst@StringUtils( stringReplaceReq )( destinationLocation );
                with(global.state){
                    .servers[i].location = destinationLocation
                }
            }
        }
    }
}

define initLeaderVar{
    undef(global.state.volatile.leader)
    for( i = 0, i < #global.state.servers, i++ ) {
        if (is_defined(global.state.servers[i].location)){
            with(global.state.volatile.leader.server[i]){
                .nextIndex = global.state.volatile.lastApplied - 1;
                .matchIndex = 0
            }
        }
    }
}

define startElectionTimer{
    // Choose election timeouts randomly in [T, 2T]
    synchronized (electionTimerToken){
        if (is_defined(global.state.internal.electionTimerId)){
            throw (TIME_NOT_CANCELED, {.message= "from server " + global.state.serverId})
        }
        start@internalTimer({.min = global.state.broadcastTime, .max = global.state.broadcastTime*2, .message="Election"})(res);
        logEvent@Logger({.serverId = global.state.serverId, .event = "start election timeout", .desc.timeout = res.timeout, .desc.id = res.id})()
        global.state.internal.electionTimerId = res.id
    }
}

define resetElectionTimer{
    synchronized (electionTimerToken){
        cancel@internalTimer(global.state.internal.electionTimerId)(res);
        logEvent@Logger({.serverId = global.state.serverId, .event="reset election timeout of id " + global.state.internal.electionTimerId + " result: " + res})();
        undef(global.state.internal.electionTimerId)
    }
}

define startHeartbeatTimer{
    // Choose heartbeat timeouts T/3
    synchronized (heartbeatTimerToken){
        if (is_defined(global.state.internal.heartBeatTimerId)){
            throw (TIME_NOT_CANCELED)
        }
        start@internalTimer({.min = global.state.broadcastTime/3, .max = global.state.broadcastTime/3, .message="Heartbeat"})(res);
        logEvent@Logger({.serverId = global.state.serverId, .event = "start heartbeat timeout", .desc.timeout = res.timeout, .desc.id = res.id})()
        global.state.internal.heartBeatTimerId = res.id
    }
}

define resetHeartbeatTimer{
    synchronized (heartbeatTimerToken){
        cancel@internalTimer(global.state.internal.heartBeatTimerId)(res);
        logEvent@Logger({.serverId = global.state.serverId, .event="reset heartbeat timeout of id " + global.state.internal.heartBeatTimerId + " result: " + res})();
        undef(global.state.internal.heartBeatTimerId)
    }
}



define broadcastRequestVoteRPC{
    // send request to every server, expected requestVoteRequest is set from election procedure
    logEvent@Logger({.serverId = global.state.serverId, .event="broadcast RequestVoteRPC", .desc = requestVoteRequest})()
    for( i = 0, i < #global.state.servers, i++ ) {
        if (is_defined(global.state.servers[i].location)){
            logEvent@Logger({.serverId = global.state.serverId, .event="sending request to port " + global.state.servers[i].location})();
            raftOutputPort.location = global.state.servers[i].location;
            requestVote@raftOutputPort(requestVoteRequest)
        }
    }
}

define broadcastAppendEntriesRPC{
    // send request to every server, expected appendEntiresRequest is set from heartbeat procedure
    logEvent@Logger({.serverId = global.state.serverId, .event="broadcast AppendEntires", .desc = requestVoteRequest})()
    for( i = 0, i < #global.state.servers, i++ ) {
        if (is_defined(global.state.servers[i].location)){
            logEvent@Logger({.serverId = global.state.serverId, .event="sending request to port " + global.state.servers[i].location})();
            raftOutputPort.location = global.state.servers[i].location;
            appendEntires@raftOutputPort(appendEntiresRequest)
        }
    }
}

/**
    procedure for sending response back to candidate
    assume the variable ackRequest is 

    type RequestVoteResponse:int{
        // currentTerm, for candidate to update itself
        term: term

        // true means candidate received vote
        voteGranted: bool
    }

    and variable req.candidateId has candidate's serverId
*/
define responseRequestVoteRPC{
    logEvent@Logger({.serverId = global.state.serverId, .event="reply RequestVoteRPC to serverId " + req.candidateId })()

    raftOutputPort.location = global.state.servers[req.candidateId].location;
    requestVoteAck@raftOutputPort(ackRequest)
}


/**
    implementation of behavior when receiving reqeustVote 
    assume the variable req is 

    type RequestVoteRequest:int{
        // Candidate's term
        term: term

        // Candidate requesting vote
        candidateId: serverId

        // index of candidate's last log entry 
        lastLogIndex: index

        // term of candidate's last log entry
        lastLogTerm: term
    }

    then procedure is building message and calling responseRequestVoteRPC to candidate
*/
define requestVoteHandler{
    scope(requestVoteHandler){
        ackRequest = global.state.serverId
        ackRequest.term = global.state.persistent.currentTerm;

        // logVar@Logger(global.state.persistent)()
        // logVar@Logger(req)()

        // denies vote to more complete log
        //(lastTermV > lastTermC) ||(lastTermV == lastTermC) && (lastIndexV > lastIndexC)
        if ((global.state.persistent.currentTerm > req.lastLogTerm) || 
                (
                    global.state.persistent.currentTerm == req.lastLogTerm && 
                    global.state.persistent.lastApplied > req.lastLogIndex
                )){
            ackRequest.voteGranted = false
        } else {
            ackRequest.voteGranted = true
        }
        // sending ack back to candidate
        responseRequestVoteRPC
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
        synchronized( currentTerm ) {
            global.state.persistent.currentTerm++
        }
        global.state.persistent.votedFor = global.state.serverId;

        
        // preparing request
        requestVoteRequest = global.state.serverId;
        with(requestVoteRequest){
            .term = global.state.persistent.currentTerm;
            .candidateId = global.state.serverId;
            .lastLogIndex = global.state.volatile.lastApplied;
            if (is_defined(global.state.persistent.logs[global.state.volatile.lastApplied].term)){
                .lastLogTerm = global.state.persistent.logs[global.state.volatile.lastApplied].term
            } else {
                .lastLogTerm = 0
            }
        };
        broadcastRequestVoteRPC
    }
}

define heartbeat{
    // broadcast AppendEntires with empty entries
    scope (heartbeat){
        appendEntiresRequest = global.state.serverId;
        with(appendEntiresRequest){
            .term = global.state.persistent.currentTerm;
            .leaderId = global.state.serverId;
            
            if (global.state.volatile.lastApplied == 0 ){
                .prevLogIndex = 0
            }else{
                .prevLogIndex = global.state.volatile.lastApplied - 1
            }
            .leaderCommit = global.state.volatile.commitIndex

            if (is_defined(global.state.persistent.logs[global.state.volatile.lastApplied - 1].term)){
                .prevLogTerm = global.state.persistent.logs[global.state.volatile.lastApplied - 1].term
            } else {
                .prevLogTerm = 0
            }
        }
        broadcastAppendEntriesRPC
    }
}

define changeToCandidate{
    logEvent@Logger({.serverId = global.state.serverId, .event = "turning to candidate"})()
    synchronized( roleToken ) {
        global.state.role = ROLE_CANDIDATE
    }
}

define changeToFollower{
    logEvent@Logger({.serverId = global.state.serverId, .event = "turning to follower"})()
    synchronized( roleToken ) {
        global.state.role = ROLE_FOLLOWER
    }
}

define changeToLeader{
    logEvent@Logger({.serverId = global.state.serverId, .event = "turning to leader"})()
    synchronized( roleToken ) {
        global.state.role = ROLE_LEADER
    }

    initLeaderVar;
    heartbeat
}

execution { concurrent }

init{
    global.state.serverId = int(SERVER_ID)
    global.state.serverAmount = int(TOTAL_SERVERS)
    // calculate majority
    if (global.state.serverAmount % 2 == 0){
        global.state.majority = global.state.serverAmount /2
    }else{
        global.state.majority = global.state.serverAmount /2 + 1 
    }

    if ( !is_defined(global.state.serverId) || !is_defined(global.state.serverAmount)  ) {
        println@Console("Please, specify server id and server amount")();
        exit
    } else {
        logEvent@Logger({.serverId = global.state.serverId, .event = "totalServer = " + global.state.serverAmount})();
        initVar;
        embbedTimer;
        logEvent@Logger({.serverId = global.state.serverId, .event = "server startup"})();
        changeToFollower;
        startElectionTimer

    }

}

main{
    [timeoutTicked()()]{
        logEvent@Logger({.serverId = global.state.serverId, .event = "timeout Ticked"})()
        // current role is follower, turn to candidate
        if ( global.state.role == ROLE_FOLLOWER){
            resetElectionTimer;
            changeToCandidate;
            election | startElectionTimer
        } else if (global.state.role == ROLE_CANDIDATE){
            // start a new election
            resetElectionTimer;
            election | startElectionTimer
        } else if (global.state.role == ROLE_LEADER){
            resetHeartbeatTimer;
            heartbeat | startHeartbeatTimer
        } else {
            throw (INVALID_ROLE, {.exceptionMessage = "server is not in valid role " + global.state.role})
        }
    }

    [requestVote(req)]{
        logEvent@Logger({.serverId = global.state.serverId, .event = "receive requestVote RPC"})()
        resetElectionTimer;
        requestVoteHandler;
        startElectionTimer
    }

    [requestVoteAck(req)]{
        synchronized(requestVoteAckToken){
            logEvent@Logger({.serverId = global.state.serverId, .event = "receive requestVoteAck RPC"})()
            logVar@Logger(req)()
            if (req.voteGranted == true){

                global.state.candidate.grantCount++

                if (global.state.candidate.grantCount == global.state.majority){
                    resetElectionTimer;
                    changeToLeader;
                    startHeartbeatTimer
                }
            }
        }
    }

    [appendEntires(req)]{
        logEvent@Logger({.serverId = global.state.serverId, .event = "receive appendEntries RPC"})();

        ackRequest = global.state.serverId
        logVar@Logger(req)()


        if (req.term == global.state.persistent.currentTerm ){
            // step-down to follower when it is a candidate
            if (global.state.role == ROLE_CANDIDATE){
                changeToFollower
            }
            synchronized(leaderToken){
                global.state.leader = req.leaderId
            }
        } else {
            // update current term
            synchronized(currentTermToken){
                global.state.persistent.currentTerm = req.term
            }
        }

        // stale term
        if (req.term < global.state.persistent.currentTerm ){
            ackRequest.success = false
            ackRequest.term = global.state.persistent.currentTerm
        } 
        // else if (){
        //     // Reject if log doesn't contain a matching previous entry.

        // }

        resetElectionTimer;
        startElectionTimer
    }
}