import area, user, message
import sets, asyncnet, asyncdispatch, strutils, sequtils, marshal

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

proc broadcastMessage(s: Server, msg: string) {.async} =
  #Broadcast a message to all users connected to the server
  for u in s.users:
    await u.socket.send(msg & "\r\L")

proc processMessage(s: Server, msg: Message, u: User) {.async.} =
  #Determine actions based upon message type
  let response =
    case msg.mType
    of MessageType.Chat:
      case msg.content.toLower()
      #List server neighbours
      of "!exits":
        "Exits: " & $(s.exits.mapIt(it.name).join(", "))
      #Short info about the server
      of "!info":
        "Name: " & s.name & "\nArea info: " & s.area.name
      #List online users
      of "!users":
        "Users: " & $(s.users.mapIt(it.name).join(", "))
      #The user has declared intent to quit the server
      of "!quit":
        s.users.excl(u)
        u.socket.close()
        u.name & " has quit the server."
      #Otherwise, it is just chat
      else:
        await s.broadcastMessage($$msg)
        ""
    of MessageType.Network:
      case msg.content.toLower()
      of "ping":
        "pong"
      else:
        ""
    #Client's cannot send authority messages
    of MessageType.Authority:
      ""

  if response != "":
    await s.broadcastMessage(msg = $$Message(content: response, mType: msg.mType, sender: s.name))

proc processUser(s: Server, user: User) {.async.} =
  #Handle a specific user
  while true:
    #The user is no longer connected, break out of this handling loop.
    if user.socket.isClosed():
      return

    #Get the message sent and log it
    let message = marshal.to[Message](await user.socket.recvLine())
    echo($$message)

    #Process the user's message
    await processMessage(s, message, user)

proc loadAndHandleUser(s: Server, c: AsyncSocket) {.async.} =
  let ident = await c.recvLine()
  var u = newUser(ident, c)

  #This is a new user
  if not s.users.contains(u):
    s.users.incl(u)
    echo("Initialized user: " & u.name)

  #We have info on this user
  else:
    echo("Loaded existing user: " & u.name)
    u = (s.users)[u]
    u.socket = c

  let joinMsg = u.name & " has joined the server."
  let encoded = $$Message(content: joinMsg, mType: MessageType.Chat, sender: s.name)
  await s.broadcastMessage(msg = encoded)

  #Begin handling the user
  asynccheck s.processUser(u)

proc serve*(s: Server, port: int) {.async.} =
  #Spin up the server
  s.socket.bindAddr(Port(port))
  s.socket.listen()

  #Loop forever to wait for new users
  while true:
    let clientSocket = await s.socket.accept()
    echo("Got new socket...")
    asynccheck s.loadAndHandleUser(clientSocket)
