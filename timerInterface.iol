type timeoutRequestType: void {
  .max: int
  .min: int
  .message: string
}

type timeoutResponseType: void {
  .id: long
  .timeout: int
}

interface TimeoutServiceInputInterface {
    RequestResponse:
      start( timeoutRequestType )( timeoutResponseType ),
      cancel( long )( bool)
    OneWay:
      timeout( any )
}

interface TimeoutServiceOutputInterface {
    RequestResponse: 
        timeoutTicked( string )(void)
}