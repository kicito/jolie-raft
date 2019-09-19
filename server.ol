include "console.iol"
include "runtime.iol"

include "constants.iol"

include "raftInterface.iol"
include "raftClientInterface.iol"

include "logger.ol"

include "timerInterface.iol"


// interfaces
inputPort myLocalPort {
  Location: LOCAL_PORT
  Protocol: sodep
  Interfaces: TimeoutServiceOutputInterface, RaftRPCInterface
}


outputPort internalTimer {
  Interfaces: TimeoutServiceInputInterface
}


inputPort raftInputPort {
    Location: RAFT_PORT
    Protocol: sodep
    Interfaces: RaftRPCInterface
}

outputPort raftOutputPort {
    Protocol: sodep
    Interfaces: RaftRPCInterface
}

inputPort clientPort {
    Location: CLIENT_PORT
    Protocol: http
    Interfaces: ClientRaftRPCInterface
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
        .logs: logEntry
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

define embedTimer{

    with( emb ) {
        .filepath = "-C LOCAL_LOCATION=\"local://server" + global.state.serverId + "\" " + 
         "-C BROADCAST_TIME=" + global.state.broadcastTime + " timerService.ol";
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
        }
        for ( i = 0, i < global.state.serverAmount, i++){
            if ( i != global.state.serverId){
                stringReplaceReq = LOCAL_PORT;
                stringReplaceReq.regex = "800" + string(global.state.serverId);
                stringReplaceReq.replacement = "800" + i;
                replaceFirst@StringUtils( stringReplaceReq )( destinationLocation );
                with(global.state){
                    .servers[i].location = destinationLocation
                }
            }
        }
        logVar@Logger(global.state)()
    }
}

define initLeaderVar{
    undef(global.state.volatile.leader)

    global.state.leaderId = global.state.serverId

    for( i = 0, i < #global.state.servers, i++ ) {
        if (is_defined(global.state.servers[i].location)){
            with(global.state.volatile.leader.server[i]){
                .nextIndex = global.state.volatile.lastApplied + 1;
                .matchIndex = 0
            }
        }
    }
}


define unDefineElectionTimer{
    synchronized(electionTimerToken){
        undef(global.state.internal.electionTimerId)
    }
}

define startElectionTimer{
    // Choose election timeouts randomly in [T, 2T]
    if (is_defined(global.state.internal.electionTimerId)){
        throw (TIME_NOT_CANCELED, {.message= "electionTimeout from server " + global.state.serverId + " with id " + global.state.internal.electionTimerId})
    }
    synchronized(eTimerToken){
        startElectionTimer@internalTimer()(electTimeoutRes);
        logEvent@Logger({.serverId = global.state.serverId, .event = "start election timeout", .desc.timeout = electTimeoutRes.param, .desc.id = electTimeoutRes.id})()
        global.state.internal.electionTimerId = electTimeoutRes.id
    }
}


define resetElectionTimer{
    if (is_defined(global.state.internal.electionTimerId)){
        synchronized(eTimerToken){
            cancel@internalTimer(global.state.internal.electionTimerId)(cancelETimeoutRes);
            logEvent@Logger({.serverId = global.state.serverId, .event="reset election timeout of id " + global.state.internal.electionTimerId + " result: " + cancelETimeoutRes})();
            unDefineElectionTimer
        }
    }
}


define unDefineHeartbeatTimer{
    synchronized(heartbeatTimerToken){
        undef(global.state.internal.heartBeatTimerId)
    }
}

define startHeartbeatTimer{
    if (is_defined(global.state.internal.heartBeatTimerId)){
        throw (TIME_NOT_CANCELED, {.message= "electionTimeout from server " + global.state.serverId})
    }
    startHeartbeatTimer@internalTimer()(hbTimeoutRes);

    logEvent@Logger({.serverId = global.state.serverId, .event = "start heartbeat timeout", .desc.timeout = hbTimeoutRes.param, .desc.id = hbTimeoutRes.id})()
    global.state.internal.heartBeatTimerId = hbTimeoutRes.id
}

define resetHeartbeatTimer{
    if (is_defined(global.state.internal.heartBeatTimerId)){
        cancel@internalTimer(global.state.internal.heartBeatTimerId)(cancelHBTimeoutRes);
        logEvent@Logger({.serverId = global.state.serverId, .event="reset heartbeat timeout of id " + global.state.internal.heartBeatTimerId + " result: " + cancelHBTimeoutRes})();
        unDefineHeartbeatTimer
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
            logEvent@Logger({.serverId = global.state.serverId, .event="sending AppendEntires request to port " + global.state.servers[i].location})();

            logVar@Logger(global.state.volatile.leader.server[i])();

            // println@Console("last log index = " + global.state.persistent.logs[#global.state.persistent.logs - 1].index + " server next index = " + global.state.volatile.leader.server[i].nextIndex + " log no = " + #global.state.persistent.logs)()
            

            if(is_defined(global.state.persistent.logs[#global.state.persistent.logs - 1])){
                // check that it should include log entries
                if ( global.state.persistent.logs[#global.state.persistent.logs - 1].index >= global.state.volatile.leader.server[i].nextIndex ){
                    // println@Console(global.state.persistent.logs[global.state.volatile.leader.server[i].nextIndex - 1].index)()
                    // println@Console(global.state.persistent.logs[global.state.volatile.leader.server[i].nextIndex - 1].term)()
                    // println@Console(global.state.persistent.logs[global.state.volatile.leader.server[i].nextIndex - 1].command)()
                    // logVar@Logger(global.state.persistent.logs[global.state.volatile.leader.server[i].nextIndex - 1])()
                    // include log at server[i].nextIndex to the request
                    appendEntiresRequest.entires = global.state.persistent.logs[global.state.volatile.leader.server[i].nextIndex - 1].index;
                    with(appendEntiresRequest.entires){
                        .index = int(global.state.persistent.logs[global.state.volatile.leader.server[i].nextIndex - 1].index);
                        .term = global.state.persistent.logs[global.state.volatile.leader.server[i].nextIndex - 1].term;
                        .command = global.state.persistent.logs[global.state.volatile.leader.server[i].nextIndex - 1].command
                    }
                    // logVar@Logger(appendEntiresRequest.entires)();
                    // logEvent@Logger({.serverId = global.state.serverId, .event="embedding log entry to request", .desc = appendEntiresRequest.entires})()
                }
            };

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

    and variable rvReq.candidateId has candidate's serverId
*/
define responseRequestVoteRPC{
    logEvent@Logger({.serverId = global.state.serverId, .event="reply RequestVoteRPC to serverId " + rvReq.candidateId + " @" + global.state.servers[rvReq.candidateId].location })()

    raftOutputPort.location = global.state.servers[rvReq.candidateId].location;
    requestVoteAck@raftOutputPort(ackRequest)
}


/**
    implementation of behavior when receiving reqeustVote 
    assume the variable rvReq is 

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
        // logVar@Logger(rvReq)()

        // denies vote to more complete log
        //(lastTermV > lastTermC) ||(lastTermV == lastTermC) && (lastIndexV > lastIndexC)
        if ((global.state.persistent.currentTerm > rvReq.lastLogTerm) || 
                (
                    global.state.persistent.currentTerm == rvReq.lastLogTerm && 
                    global.state.volatile.lastApplied > rvReq.lastLogIndex
                )){
            ackRequest.voteGranted = false
        } else {
            ackRequest.voteGranted = true
        }
        // sending ack back to candidate
        if (ackRequest.voteGranted != true){
            logEvent@Logger({.serverId = global.state.serverId, .event="decline requestVote", 
                .desc.self.currentTerm=global.state.persistent.currentTerm, 
                .desc.self.lastApplied=global.state.volatile.lastApplied,
                .desc.req.lastLogTerm=rvReq.lastLogTerm,
                .desc.req.lastLogIndex=rvReq.lastLogIndex
            })()
            responseRequestVoteRPC

        }else{
            responseRequestVoteRPC | startElectionTimer

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

    logVar@Logger(global.state.volatile.leader)();
    appendEntiresRequest = global.state.serverId;
    with(appendEntiresRequest){
        .term = global.state.persistent.currentTerm;
        .leaderId = global.state.serverId;
        
        if (global.state.volatile.lastApplied == 0 ){
            .prevLogIndex = 0
        }else{
            .prevLogIndex = global.state.volatile.lastApplied - 1
        };
        .leaderCommit = global.state.volatile.commitIndex;

        logVar@Logger(global.state.persistent.logs)()
        logVar@Logger(global.state.volatile)()

        if (is_defined(global.state.persistent.logs[global.state.volatile.lastApplied - 1].term)){
            .prevLogTerm = global.state.persistent.logs[global.state.volatile.lastApplied - 1].term
        } else {
            .prevLogTerm = 0
        }
    };
    logVar@Logger(appendEntiresRequest)();

    broadcastAppendEntriesRPC
}

define changeToCandidate{
    logEvent@Logger({.serverId = global.state.serverId, .event = "turning to candidate"})()
    synchronized( roleToken ) {
        global.state.role = ROLE_CANDIDATE
    }
    global.state.candidate.grantCount = 0
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
        embedTimer;
        logEvent@Logger({.serverId = global.state.serverId, .event = "server startup"})();
        changeToFollower;
        startElectionTimer

    }

}

main{
    [electionTimeoutTicked(timeoutMsg)]{
        synchronized(handlerToken){
            logEvent@Logger({.serverId = global.state.serverId, .event = "eletion ticked, current role " + global.state.role})();
            unDefineElectionTimer
            // current role is follower, turn to candidate
            if ( global.state.role == ROLE_FOLLOWER ){
                changeToCandidate;
                election | startElectionTimer
            } else if (global.state.role == ROLE_CANDIDATE){
                // start a new election
                election | startElectionTimer
            } else {
                throw (INVALID_ROLE, {.exceptionMessage = "server is not in valid role " + global.state.role})
            }
        }
    }

    [heartbeatTimeoutTicked(timeoutMsg)]{
        synchronized(handlerToken){
            logEvent@Logger({.serverId = global.state.serverId, .event = "heartbeat ticked, current role " + global.state.role})();
            unDefineHeartbeatTimer;
            if (global.state.role == ROLE_LEADER){
                heartbeat | startHeartbeatTimer
            } else {
                throw (INVALID_ROLE, {.exceptionMessage = "server is not in valid role " + global.state.role})
            }
        }
    }

    [requestVote(rvReq)]{
        synchronized(handlerToken){
            logEvent@Logger({.serverId = global.state.serverId, .event = "receive requestVote RPC"})();
            resetElectionTimer;
            requestVoteHandler
        }
    }

    [requestVoteAck(rvAckreq)]{
        synchronized(handlerToken){
            logEvent@Logger({.serverId = global.state.serverId, .event = "receive requestVoteAck RPC"})()
            if (rvAckreq.voteGranted == true){

                global.state.candidate.grantCount++

                if (global.state.candidate.grantCount == global.state.majority){
                    resetElectionTimer;
                    changeToLeader;
                    startHeartbeatTimer
                }
            }
        }
    }

    [appendEntires(aeReq)]{
        synchronized(handlerToken){
            logEvent@Logger({.serverId = global.state.serverId, .event = "receive appendEntries RPC"})();

            ackRequest = global.state.serverId;


            if (aeReq.term == global.state.persistent.currentTerm ){
                // step-down to follower when it is a candidate
                if (global.state.role == ROLE_CANDIDATE){
                    resetElectionTimer;
                    changeToFollower
                }
            } else {
                // update current term
                synchronized(currentTermToken){
                    global.state.persistent.currentTerm = aeReq.term
                }
            }


            synchronized(leaderToken){
                global.state.leaderId = aeReq.leaderId
            }

            // stale term
            if (aeReq.term < global.state.persistent.currentTerm ){
                ackRequest.success = false
                ackRequest.term = global.state.persistent.currentTerm
            } 
            if (is_defined(aeReq.entires)){
                println@Console("received log entry")()
                logVar@Logger(aeReq.entires)()
            }
            // else if (){
            //     // Reject if log doesn't contain a matching previous entry.

            // }

            resetElectionTimer;
            startElectionTimer
        }
    }

    [add(addReq)(addRes){
        synchronized(handlerToken){
            logVar@Logger(addReq)()
            // if the server is not leader, send redirection
            if (!is_defined(global.state.leaderId)){
                addRes.success = false;
                addRes.message = "no leader registered"
            } else if(global.state.leaderId != global.state.serverId){
                addRes.success = false;
                addRes.message = "redirect to server " + global.state.leaderId
            } else {
                addRes.success = true;
                addRes.message = "appending value " + addReq.value + " to system";
                totalLogAmt = #global.state.persistent.logs
                println@Console("current log entries = " + #global.state.persistent.logs)()
                with(global.state.persistent){
                    .logs[totalLogAmt].index = global.state.volatile.lastApplied + 1;
                    .logs[totalLogAmt].term = global.state.persistent.currentTerm;
                    .logs[totalLogAmt].command = addReq.value
                }
                println@Console("current log entries = " + #global.state.persistent.logs)()
                logVar@Logger(global.state.persistent.logs[totalLogAmt])()

                global.state.volatile.lastApplied++

            }
            logVar@Logger(addRes)()
        }
    }]
}