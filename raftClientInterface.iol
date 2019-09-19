

type ClientRequestType : void {
    value: any
}

type ClientResponseType : void {
    success: bool
    message: any
}

interface ClientRaftRPCInterface{
    RequestResponse:
        add(ClientRequestType)(ClientResponseType)
}