type
  MessageType*{.pure.} = enum
    Network, Authority, Chat
  Message* = object
    content*: string
    sender*: string
    mType*: MessageType
