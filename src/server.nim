import area, user, message
import sets, asyncnet, asyncdispatch, strutils, sequtils, marshal, tables

type
  Server* = ref ServerObj
  ServerObj = object
    name*: string
    area*: Area
    users*: HashSet[User]
    exits*: seq[string]
    externals*: Table[MessageType, string]
    socket: AsyncSocket
    port*: Port

proc newServer*(name: string, area: Area): Server =
  new(result)
  result.name = name
  result.area = area
  result.users = initSet[User]()
  result.exits = @[]
  result.externals = initTable[MessageType, string]()
  result.socket = newAsyncSocket()

#TODO: Consider adding a recipients set parameter.
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
        #Choose not to broadcast here, causes crashes.
        #u.name & " has quit the server service " & $socket
        ""
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
  #Listen for messages on the socket
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

    try:
      let message = marshal.to[Message](await user.sockets[m].recvLine())
      await processMessage(s, message, user, m)
    except:
      echo("Bad message passed!")

proc loadAndHandleSocket(s: Server, c: AsyncSocket) {.async.} =
  #Handle server entrance logic for the socket

  #Don't try to just directly parse the enum, assume a failure
  let enumLine = (await c.recvLine())
  let m =
    try:
      parseEnum[MessageType](enumLine)
    except:
      echo("Bad enum value, got " & enumLine)
      c.close()
      return
      MessageType.Authority

  let ident = await c.recvLine()
  var u = newUser(ident, c)

  echo("Socket is identifying as " & ident & " and requesting service " & $m)

  #Transfer logic
  if s.externals.hasKey(m):
    #We can't transfer someone who isn't already here (yet?)
    if s.users.contains(u):
      #Add the new socket to our current user
      s.users[u].sockets[m] = c

      #Shadow old u for brevity
      u = s.users[u]

      #Inform the socket of where to switch to
      let msg = Message(content: "connect " & s.externals[m] & " for " & $m, mType: MessageType.Authority, sender: s.name)
      await u.sockets[MessageType.Authority].send($$msg & "\r\L")

      #Once the message has been sent, close the socket and log it.
      u.sockets[m].close()
      echo("Sent to: " & s.externals[m] & " for " & $m)
    #Even if we couldn't transfer, return anyway. Nothing we can do anymore.
    return

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
    await s.loadAndHandleSocket(clientSocket)

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

      #Externals show up like MessageType=Hostname:Port,...
      #If there isn't an external, it reads MessageType,...
      let externalStrings = f.readLine().strip().split(",").mapIt(it.strip())
      let extSplits = externalStrings.mapIt(it.split("="))
      var externals = initTable[MessageType, string]()
      for pair in extSplits:
        if len(pair) > 1:
          externals[parseEnum[MessageType](pair[0])] = pair[1]

      var serveOne = newServer(area = newArea(areaName), name = name)
      serveOne.port = port
      serveOne.exits = exits
      serveOne.externals = externals

      asyncCheck serveOne.serve()

      runForever()
    else:
      echo("Could not open file: " & filepath)
      quit()
  main()
