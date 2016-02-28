import area, server, user, sets, sequtils, strutils
import asyncnet, asyncdispatch, threadpool

proc readMessages(): string =
  result = stdin.readLine()

proc printMessages(s: AsyncSocket) {.async.} =
  while true:
    let line = await s.recvLine()
    echo(line)

proc sendMessages(s: AsyncSocket) {.async.} =
  var messageFlowVar = spawn readMessages()
  while true:
    if messageFlowVar.isReady():
      asyncCheck s.send((^messageFlowVar).strip() & "\r\L")
      messageFlowVar = spawn readMessages()
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
