import area, server, user
import asyncnet, asyncdispatch, threadpool, sets, sequtils, strutils

proc readMessages(): string =
  #Helper function so that input can be nonblocking
  result = stdin.readLine()

proc printMessages(s: AsyncSocket) {.async.} =
  #Loop forever until we get a message, then print it
  while true:
    let line = await s.recvLine()
    echo(line)

proc sendMessages(s: AsyncSocket) {.async.} =
  #Async proc to send messages on a socket

  #Hold the message in a future
  var messageFlowVar = spawn readMessages()


  while true:
    #If we have a message...
    if messageFlowVar.isReady():
      let msg = (^messageFlowVar).strip()

      #Send it in the proper format
      asyncCheck s.send(msg & "\r\L")

      #and restart the background read proc
      messageFlowVar = spawn readMessages()

      if msg.toLower() == "!quit":
        s.close()
        quit()

    #Make sure to poll for events!
    asyncdispatch.poll()

proc main() {.async.} =
  var s = newAsyncSocket()
  await s.connect("127.0.0.1", Port(12345))

  echo("Enter a nickname")
  let nick = stdin.readLine().strip() & "\r\L"
  await s.send(nick)

  asyncCheck s.printMessages()
  asyncCheck s.sendMessages()

asyncCheck main()
runForever()
