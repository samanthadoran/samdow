import user, message
import asyncnet, asyncdispatch, threadpool, sets, sequtils, strutils, marshal

proc readMessages(): string =
  #Helper function so that input can be nonblocking
  result = stdin.readLine()

proc handleMessages(u: User, m: MessageType) {.async.} =
  while true:
    #Keep the proc going, but don't listen for messages on a dead socket
    if u.sockets[m].isClosed():
      echo("Socket " & $m & " is closed???")
      continue
    if u.sockets[m] == nil:
      echo("Socket " & $m & " is nil???")
      continue

    let msg = marshal.to[Message](await u.sockets[m].recvLine())

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
        await u.sockets[m].send($$Message(content: "pong", sender: u.name, mType: msg.mType))
      else:
        echo($$msg)
    of MessageType.Authority:
      case msgTokens[0]
      #Drop a server for a specific service
      #Of the form drop MessageType
      of "drop":
        let messageType = parseEnum[MessageType](msgTokens[1])
        u.sockets[messageType].close()
      #Connect to a server for a specific message type
      #Of the form connect hostname:port for MessageType
      of "connect":
        #Format the address
        let splitAddress = msgTokens[1].split(":")
        #Parse the type
        let external = parseEnum[MessageType](msgTokens[3])

        if u.sockets[external] != nil and not u.sockets[external].isClosed():
          u.sockets[external].close()

        #Init the new socket and hook it in
        u.sockets[external] = newAsyncSocket()
        await u.sockets[external].connect(splitAddress[0], Port(splitAddress[1].parseInt()))
        await u.sockets[external].send($external & "\r\L")
        await u.sockets[external].send(u.name & "\r\L")
        asyncCheck u.handleMessages(external)
        return
      else:
        discard

proc sendMessages(u: User) {.async.} =
  #Async proc to send messages on a socket

  #Hold the message in a future
  var messageFlowVar = spawn readMessages()
  while true:
    #Don't try to send chat on an empty socket...
    #If we have a message...
    if messageFlowVar.isReady() and not u.sockets[MessageType.Chat].isClosed():
      let msg = (^messageFlowVar).strip()

      let encodedMessage = Message(content: msg, mType: MessageType.Chat, sender: u.name)

      #Special check for quit, send in this order to prevent crashing.
      if msg.toLower() == "!quit":
        for m in MessageType:
          await u.sockets[m].send($$encodedMessage & "\r\L")
          u.sockets[m].close()
        quit()

      #Send it in the proper format
      await u.sockets[MessageType.Chat].send($$encodedMessage & "\r\L")

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

  var u = newUser(nick, nil)

  #Connect to the initial server for all services
  for m in MessageType:
    u.sockets[m] = newAsyncSocket()
    await u.sockets[m].connect(address, port)
    await u.sockets[m].send($m & "\r\L")
    await u.sockets[m].send(nick & "\r\L")

  for m in MessageType:
    asyncCheck u.handleMessages(m)
  asyncCheck u.sendMessages()

asyncCheck main()
runForever()
