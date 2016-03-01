import message
import hashes, asyncnet, sets

type
  User* = ref UserObj
  UserObj = object
    name*: string
    socket*: AsyncSocket
    sockets*: array[MessageType.low..MessageType.high, AsyncSocket]

proc hash*(u: User): Hash =
  result = u.name.hash
  result = !$result

proc newUser*(name: string, socket: AsyncSocket): User =
  new(result)
  result.name = name
  for t in MessageType:
    result.sockets[t] = socket

proc `$`*(u: User): string =
  #Set proc `[]` requires its keys to have `$` defined, appease it.
  result = u.name
