import area, user
import sets, tables, asyncnet, asyncdispatch, strutils, sequtils

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

proc broadcastMessage(s: Server, msg: string, sender: string) {.async} =
  if msg != "":
    for u in s.users:
      await u.socket.send(sender & ": " & msg & "\r\L")
      echo("Sent message: " & msg & " to " & u.name)

proc processMessage(s: Server, msg: string, u: User) {.async.} =
  #Determine if a user typed a command
  let response =
    case msg.toLower()
    of "!exits":
      "Exits: " & $(s.exits.mapIt(it.name).join(", "))
    of "!info":
      "Name: " & s.name & "\nArea info: " & s.area.name
    of "!users":
      "Users: " & $(s.users.mapIt(it.name).join(", "))
    of "!quit":
      s.users.excl(u)
      u.socket.close()
      u.name & " has quit the server."
    else:
      ""

  await s.broadcastMessage(msg = response, sender = s.name)

proc processUser(s: Server, user: User) {.async.} =
  while true:
    if user.socket.isClosed():
      return

    let line = await user.socket.recvLine()
    echo(user.name & ": " & line)

    await s.broadcastMessage(msg = line, sender = user.name)

    #After sending the users what was said, process it
    await processMessage(s, line, user)

proc processClient(s: Server, c: AsyncSocket) {.async.} =
  while true:
    let ident = await c.recvLine()
    var u = newUser(ident, c)
    s.users.incl(u)
    echo("Initialized user: " & u.name)

    let joinMsg = u.name & " has joined the server."
    await s.broadcastMessage(msg = joinMsg, sender = s.name)

    asynccheck s.processUser(u)
    return

proc serve*(s: Server, port: int) {.async.} =
  s.socket.bindAddr(Port(port))
  s.socket.listen()

  while true:
    let clientSocket = await s.socket.accept()
    echo("Got new socket...")
    asynccheck s.processClient(clientSocket)
