import user, message
import asyncnet, asyncdispatch, threadpool, sets, sequtils, strutils, marshal

proc handleHeartbeat(u: User, m: MessageType) {.async.} =
  #TODO: Implement
  discard

proc connectServer(u: User, m: MessageType, address: string, port: Port) {.async.} =
  #Helper function to connect a user to a server for a message type
  var
    (heartbeat, socket) = u.sockets[m]
  #Decide whether to connect the heartbeat or socket
  if heartbeat == nil or heartbeat.isClosed():
    heartbeat = newAsyncSocket()
    await heartbeat.connect(address, port)
    await heartbeat.send($m & "\r\L")
    await heartbeat.send(u.name & "\r\L")
    u.sockets[m].heartbeat = heartbeat
  else:
    socket = newAsyncSocket()
    await socket.connect(address, port)
    await socket.send($m & "\r\L")
    await socket.send(u.name & "\r\L")
    u.sockets[m].socket = socket

proc readMessages(): string =
  #Helper function so that input can be nonblocking
  result = stdin.readLine()

proc handleMessages(u: User, m: MessageType) {.async.} =
  while true:
    #Keep the proc going, but don't listen for messages on a dead socket
    var
      (heartbeat, socket) = u.sockets[m]
    if socket.isClosed():
      echo("Socket " & $m & " is closed???")
      continue
    if socket == nil:
      echo("Socket " & $m & " is nil???")
      continue

    #Don't try to use a bad message
    let mLine = await socket.recvLine()
    let msg =
      try:
        marshal.to[Message](mLine)
      except:
        Message(content: "", mType: MessageType.Network, sender: "")

    let msgTokens = msg.content.toLower().split()
    if len(msgTokens) == 0:
      echo("The message was zero length?")
      continue

    case m
    of MessageType.Chat:
      echo(msg.sender & ": " & msg.content)
    of MessageType.Network:
      case msgTokens[0]
      of "ping":
        await socket.send($$Message(content: "pong", sender: u.name, mType: msg.mType))
      else:
        echo($$msg)
    of MessageType.Authority:
      case msgTokens[0]
      #Drop a server for a specific service
      #Of the form drop MessageType
      of "drop":
        let messageType = parseEnum[MessageType](msgTokens[1])
        var
          (heartbeat, socket) = u.sockets[messageType]
        heartbeat.close()
        socket.close()
      #Connect to a server for a specific message type
      #Of the form connect hostname:port for MessageType
      of "connect":
        #Format the address
        let splitAddress = msgTokens[1].split(":")
        #Parse the type
        let external = parseEnum[MessageType](msgTokens[3])
        var
          (heartbeat, socket) = u.sockets[external]

        heartbeat.close()
        if socket != nil and not socket.isClosed():
          socket.close()

        #Connect heartbeat and socket
        await u.connectServer(external, splitAddress[0], Port(splitAddress[1].parseInt()))
        await u.connectServer(external, splitAddress[0], Port(splitAddress[1].parseInt()))
        asyncCheck u.handleHeartbeat(external)
        asyncCheck u.handleMessages(external)
        break
      else:
        discard

proc sendMessages(u: User) {.async.} =
  #Async proc to send messages on a socket

  #Hold the message in a future
  var messageFlowVar = spawn readMessages()
  while true:
    var chatSocket = u.sockets[MessageType.Chat].socket
    #Don't try to send chat on an empty socket...
    #If we have a message...
    if messageFlowVar.isReady() and not chatSocket.isClosed():
      let msg = (^messageFlowVar).strip()

      let encodedMessage = Message(content: msg, mType: MessageType.Chat, sender: u.name)

      #Special check for quit, send in this order to prevent crashing.
      if msg.toLower() == "!quit":
        for m in MessageType:
          await u.sockets[m].heartbeat.send($$encodedMessage & "\r\L")
          u.sockets[m].heartbeat.close()
          await u.sockets[m].socket.send($$encodedMessage & "\r\L")
          u.sockets[m].socket.close()
        quit()

      #Send it in the proper format
      await chatSocket.send($$encodedMessage & "\r\L")

      #and restart the background read proc
      messageFlowVar = spawn readMessages()

    #Make sure to poll for events!
    asyncdispatch.poll()

proc main() {.async.} =
  echo("Enter the address of the server you would like to connect to")
  let address = stdin.readLine().strip()

  echo("Enter its port")
  let port = Port(stdin.readLine.strip().parseInt())


  echo("Enter a nickname")
  let nick = stdin.readLine().strip()

  var u = newUser(nick)

  #Connect to the initial server for all services
  for m in MessageType:
    #Connect heartbeat and socket of type m
    await u.connectServer(m, address, port)
    await u.connectServer(m, address, port)

  for m in MessageType:
    asyncCheck u.handleHeartbeat(m)
    asyncCheck u.handleMessages(m)
  asyncCheck u.sendMessages()

asyncCheck main()
runForever()
