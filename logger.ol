include "string_utils.iol"
include "json_utils.iol"

type anyType: any{?}
type eventMsg: void{
  serverId: int
  event: string
  desc?: anyType
}

interface LoggerIface{
    RequestResponse: 
      logVar(anyType)(anyType),
      logEvent(eventMsg)(anyType)
}

service Logger{
  Interfaces: LoggerIface
  main{
    [ logVar( req )( res ) {
      nullProcess
      // valueToPrettyString@StringUtils( req )( res );
      // println@Console(res)()
    }]
    [ logEvent( req )( res ) {
      getJsonString@JsonUtils( req )( res );
      println@Console(res)()
    }]
  }
}