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
        start( timeoutRequestType )( timeoutResponseType )
    OneWay:
      timeout( any ),
      cancel( int )

}

interface TimeoutServiceOutputInterface {
    RequestResponse: 
        timeoutTicked( void )(void)
}