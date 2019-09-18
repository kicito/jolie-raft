type index: int // commit index
type serverId: int
type term: int

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

type RequestVoteResponse:int{
    // currentTerm, for candidate to update itself
    term: term

    // true means candidate received vote
    voteGranted: bool
}

// Invoked by leader to replicate log entires; also used as heartbeat
type AppendEntriesRequest:int{
    
    // leader's teem
    term: term

    // so follower can redirect client
    leaderId: serverId

    // index of log entry immediately preceeding new ones
    prevLogIndex: index

    // term of prevLogIndex entry
    prevLogTerm: term

    // log entries to store (empty for heartbeat)
    entires?: any

    // leader's commitIndex
    leaderCommit: index
}

type AppendEntriesResponse:int{
    // currentTerm, for leader to update itself
    term: term

    // true if follower contained entry matching prevLogIndex and prevLogTerm
    voteGranted: bool

}


interface RaftRPCInterface{
    OneWay: 
        appendEntires(AppendEntriesRequest),
        appendEntiresAck(AppendEntriesResponse),
        requestVote(RequestVoteRequest),
        requestVoteAck(RequestVoteResponse)

}