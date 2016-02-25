import area, user, sets, tables, asyncnet, asyncdispatch, strutils, sequtils
type
  Server* = ref ServerObj
  ServerObj = object
    name*: string
    area*: Area
    users*: HashSet[User]
    exits*: seq[Server]
    socket: AsyncSocket

proc newServer*(name: string, area: Area): Server =
  new(result)
  result.name = name
  result.area = area
  result.users = initSet[User]()
  result.exits = @[]
  result.socket = newAsyncSocket()



proc processUser(s: Server, user: User) {.async.} =
  while true:
    if user.socket.isClosed():
      s.users.excl(user)
      return
    let line = await user.socket.recvLine()
    echo(user.name & " " & line)

    for u in s.users:
      await u.socket.send(user.name & ": " & line & "\r\L")
      echo("Sent message: " & line & " to " & u.name)

proc processClient(s: Server, c: AsyncSocket) {.async.} =
  while true:
    let ident = await c.recvLine()
    var u = newUser(ident, c)
    s.users.incl(u)
    echo("Initialized user: " & u.name)

    asynccheck s.processUser(u)
    return

proc serve*(s: Server, port: int) {.async.} =
  s.socket.bindAddr(Port(port))
  s.socket.listen()

  while true:
    let clientSocket = await s.socket.accept()
    echo("Got new socket...")
    asynccheck s.processClient(clientSocket)
