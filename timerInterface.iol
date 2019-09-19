type timeoutResponseType: void {
  .id: long
  .param: any
}

interface TimeoutServiceInputInterface {
    RequestResponse:
      startElectionTimer( void )( timeoutResponseType ),
      startHeartbeatTimer( void )( timeoutResponseType ),
      cancel( long )( bool)
    OneWay:
      timeout( any )
}

interface TimeoutServiceOutputInterface {
    OneWay: 
        electionTimeoutTicked( any ),
        heartbeatTimeoutTicked( any )
}