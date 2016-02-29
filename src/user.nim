import hashes, asyncnet, sets

type
  User* = ref UserObj
  UserObj = object
    name*: string
    socket*: AsyncSocket

proc hash*(u: User): Hash =
  result = u.name.hash
  result = !$result

proc newUser*(name: string, socket: AsyncSocket): User =
  new(result)
  result.name = name
  result.socket = socket

proc `$`*(u: User): string =
  #Set proc `[]` requires its keys to have `$` defined, appease it.
  result = u.name
