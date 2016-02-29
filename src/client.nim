#import area, server, user, message
import area, user, message
import asyncnet, asyncdispatch, threadpool, sets, sequtils, strutils, marshal

proc readMessages(): string =
  #Helper function so that input can be nonblocking
  result = stdin.readLine()

proc handleMessages(u: User) {.async.} =
  #Loop forever until we get a message, then print it
  while not u.socket.isClosed():
    let msg = marshal.to[Message](await u.socket.recvLine())
    case msg.mType
    of MessageType.Chat:
      echo(msg.sender & ": " & msg.content)
    of MessageType.Network:
      case msg.content.toLower()
      of "ping":
        await u.socket.send($$Message(content: "pong", sender: u.name, mType: msg.mType))
      else:
        discard
    of MessageType.Authority:
      case msg.content.toLower()
      of "dropping":
        u.socket.close()
        discard
      of "connect":
        discard
      else:
        discard
      discard

proc sendMessages(u: User) {.async.} =
  #Async proc to send messages on a socket

  #Hold the message in a future
  var messageFlowVar = spawn readMessages()


  while not u.socket.isClosed():
    #If we have a message...
    if messageFlowVar.isReady():
      let msg = (^messageFlowVar).strip()

      let encodedMessage = Message(content: msg, mType: MessageType.Chat, sender: u.name)

      #Send it in the proper format
      await u.socket.send($$encodedMessage & "\r\L")

      #and restart the background read proc
      messageFlowVar = spawn readMessages()

      if msg.toLower() == "!quit":
        u.socket.close()

    #Make sure to poll for events!
    asyncdispatch.poll()

  quit()

proc main() {.async.} =
  var s = newAsyncSocket()

  echo("Enter the address of the server you would like to connect to")
  let address = stdin.readLine().strip()

  echo("Enter its port")
  let port = Port(stdin.readLine.strip().parseInt())

  await s.connect(address, port)

  echo("Enter a nickname")
  let nick = stdin.readLine().strip()
  var u = newUser(nick, s)
  await u.socket.send(nick & "\r\L")

  asyncCheck u.handleMessages()
  asyncCheck u.sendMessages()

asyncCheck main()
runForever()
