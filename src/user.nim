import hashes, asyncnet

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
