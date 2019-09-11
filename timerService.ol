include "math.iol"
include "runtime.iol"
include "console.iol"

include "logger.ol"

include "timerInterface.iol"
include "raftInterface.iol"


inputPort internalIn {
  Location: "local"
  Interfaces: TimeoutServiceInputInterface
}

outputPort internalOut{
  Location: LOCAL_LOCATION
  Interfaces: TimeoutServiceOutputInterface
}

execution{ concurrent }
main {
  [start( request )( res ) {
    random@Math()(delay);

    TimerReq = int(delay * (request.max - request.min)) + 1 + request.min;
    with(TimerReq){
      .message="timeout"
    };
    res.timeout = TimerReq;

    scheduleTimeout@Time( TimerReq )( res.id )
  }]


	[timeout(msg)] {
    timeoutTicked@internalOut()()
	}

  // cancel(){

  // }
}