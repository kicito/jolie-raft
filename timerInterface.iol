type timeoutRequestType: void {
  .max: int
  .min: int
}

type timeoutResponseType: void {
  .id: long
  .timeout: int
}

interface TimeoutServiceInputInterface {
    RequestResponse:
      start( timeoutRequestType )( timeoutResponseType ),
      cancel( int )( bool)
    OneWay:
      timeout( any )

}

interface TimeoutServiceOutputInterface {
    RequestResponse: 
        timeoutTicked( void )(void)
}