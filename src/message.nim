type
  MessageType*{.pure.} = enum
    Network, Chat, Authority
  Message* = object
    content*: string
    sender*: string
    mType*: MessageType
