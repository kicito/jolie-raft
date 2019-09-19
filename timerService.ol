include "math.iol"
include "runtime.iol"
include "console.iol"
include "time.iol"

include "logger.ol"

include "timerInterface.iol"
include "raftInterface.iol"


inputPort internalIn {
  Location: "local"
  Interfaces: TimeoutServiceInputInterface
}

outputPort internalOut{
  Location: LOCAL_PORT
  Protocol: sodep
  Interfaces: TimeoutServiceOutputInterface
}

execution{ concurrent }

init{
  global.broadcastTime = int(BROADCAST_TIME)

  global.electionInterval.min = double(global.broadcastTime*2)
  global.electionInterval.max = double(global.broadcastTime*3)
}

main {
  [startElectionTimer( request )( res ) {
    random@Math()(delay);
    TimerReq = int(global.electionInterval.min + delay / (1.0 / double(global.electionInterval.max - global.electionInterval.min + 1)) + 1);
    with(TimerReq){
      .message = "ELECTION"
    };
    res.param = TimerReq;

    scheduleTimeout@Time( TimerReq )( res.id )
  }]

  [startHeartbeatTimer( request )( res ) {
    TimerReq = global.broadcastTime;
    with(TimerReq){
      .message = "HEARTBEAT"
    };
    res.param = TimerReq;

    scheduleTimeout@Time( TimerReq )( res.id )
  }]


	[timeout(msg)] {
    // logVar@Logger(msg)()
    if(msg == "ELECTION"){
      electionTimeoutTicked@internalOut(msg)
    }else if (msg == "HEARTBEAT"){
      heartbeatTimeoutTicked@internalOut(msg)
    }
	}

  [cancel(id)(isSuccess){
    cancelTimeout@Time( id )( isSuccess )
  }]
}