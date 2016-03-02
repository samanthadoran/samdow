import area, user, message
import sets, asyncnet, asyncdispatch, strutils, sequtils, marshal, threadpool

type
  Server* = ref ServerObj
  ServerObj = object
    name*: string
    area*: Area
    users*: HashSet[User]
    exits*: seq[string]
    socket: AsyncSocket
    port*: Port

proc newServer*(name: string, area: Area): Server =
  new(result)
  result.name = name
  result.area = area
  result.users = initSet[User]()
  result.exits = @[]
  result.socket = newAsyncSocket()

proc broadcastMessage(s: Server, msg: Message) {.async} =
  #Broadcast a message to all users connected to the server
  for u in s.users:
    if u.sockets[msg.mType] != nil and not u.sockets[msg.mType].isClosed():
      await u.sockets[msg.mType].send($$msg & "\r\L")

proc processMessage(s: Server, msg: Message, u: User, socket: MessageType) {.async.} =
  #Determine actions based upon message type
  echo($socket & " " & $$msg)
  let response =
    case msg.mType
    of MessageType.Chat:
      case msg.content.toLower()
      #List server neighbours
      of "!exits":
        "Exits: " & $(s.exits.mapIt(it).join(", "))
      #Short info about the server
      of "!info":
        "Name: " & s.name & "\nArea info: " & s.area.name
      #List online users
      of "!users":
        "Users: " & $(s.users.mapIt(it.name).join(", "))
      #The user has declared intent to quit the server
      of "!quit":
        u.sockets[socket].close()
        u.name & " has quit the server service " & $socket
      #Otherwise, it is just chat
      else:
        await s.broadcastMessage(msg)
        ""
    of MessageType.Network:
      case msg.content.toLower()
      of "ping":
        "pong"
      else:
        echo($$msg)
        ""
    #Client's cannot send authority messages
    of MessageType.Authority:
      ""

  if response != "":
    await s.broadcastMessage(Message(content: response, mType: msg.mType, sender: s.name))

proc handleMessageType(s: Server, user: User, m: MessageType) {.async.} =
  echo("***In handleMessageType for: " & user.name & "'s " & $m)
  while true:
    #Do we need tostop processing this message type?
    if user.sockets[m] == nil or user.sockets[m].isClosed():
      #Check whether all sockets are closed, if so, disconnect.
      var disconnect: bool = true
      for s in user.sockets:
        if s != nil and not s.isClosed():
          disconnect = false
      if disconnect:
        s.users.excl(user)
        echo("Disconnecting " & user.name & " from all services.")
      break

    let message = marshal.to[Message](await user.sockets[m].recvLine())
    await processMessage(s, message, user, m)

proc loadAndHandleUser(s: Server, c: AsyncSocket) {.async.} =
  let m = parseEnum[MessageType](await c.recvLine())
  let ident = await c.recvLine()
  var u = newUser(ident, c)
  echo("Socket is identifying as " & ident & " and requesting service " & $m)

  #This is a new user
  if not s.users.contains(u):
    for mt in MessageType:
      if mt != m:
        u.sockets[mt] = nil
    s.users.incl(u)
    echo("Initialized user: " & u.name)
  #We have info on this user
  else:
    echo("Loaded existing user: " & u.name)
    u = (s.users)[u]
    u.sockets[m] = c

  let joinMsg = u.name & " has joined the server for " & $m
  let encoded = Message(content: joinMsg, mType: MessageType.Chat, sender: s.name)
  await s.broadcastMessage(msg = encoded)

  #Begin handling the user
  asyncCheck s.handleMessageType(u, m)

proc serve*(s: Server) {.async.} =
  #Spin up the server
  s.socket.bindAddr(s.port)
  s.socket.listen()

  #Loop forever to wait for new users
  while true:
    let clientSocket = await s.socket.accept()
    echo("Got new socket...")
    await s.loadAndHandleUser(clientSocket)

when isMainModule:
  import os

  proc main() =
    let filepath = if paramCount() > 0: paramStr(1) else: ""
    if filepath == "":
      echo("Please supply a file to configure server")
      quit()

    var f: File
    if open(f, filepath):
      let name = f.readLine().strip()
      let port =
        try:
          Port(f.readLine().strip().parseInt())
        except ValueError:
          echo("Bad port value, expected a number")
          quit()
          Port(0)

      let areaName = f.readLine().strip()
      let exits = f.readLine().strip().split(",").mapIt(it.strip())

      var serveOne = newServer(area = newArea(areaName), name = name)
      serveOne.port = port
      serveOne.exits = exits

      asyncCheck serveOne.serve()

      runForever()
    else:
      echo("Could not open file: " & filepath)
      quit()
  main()
