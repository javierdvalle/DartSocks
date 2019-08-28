import 'dart:core';
import 'dart:async';
import 'dart:io';


bool SHOW_DEBUG = false;
bool SHOW_ERRORS = true;
bool SHOW_INFO = true;

void printDebug(var s) { if (SHOW_DEBUG) print(s); }
void printError(var s) { if (SHOW_ERRORS) print(s); }
void printInfo(var s) { if (SHOW_INFO) print(s); }


Map parseSocksRequest(data) {
  if (data.length < 9) {
    printError('error, message too small');
    return null;
  }

  var version = data[0];
  if (version != 4) {
    printError('version not supported');
    return null;
  }

  var command = data[1] == 1 ? 'connect' : 'bind';

  var portTuple = data.sublist(2,4);
  var port = portTuple[0] * 256 + portTuple[1];

  var ipTuple = data.sublist(4, 8);
  var ip = "${ipTuple[0]}.${ipTuple[1]}.${ipTuple[2]}.${ipTuple[3]}";

  var userId = data.sublist(8, data.length-1);

  var nullEnd = data[data.length-1];
  if (nullEnd != 0) {
    printError('error, invalid format of message');
    return null;
  }

  return {
    'version': version,
    'command': command,
    'port': port,
    'portTuple': portTuple,
    'ip': ip,
    'ipTuple': ipTuple,
    'userId': userId
  };
}


List<int> buildRejectedResponse() {
  return [0x00, 0x5b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
}


List<int> buildGrantedResponse() {
  return [0x00, 0x5a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
}


class DartSocks4 {

  ServerSocket mainSocket = null;  
  
  bool start(port, {Function onDone, Function onError}) {

    if (onDone == null) {
      onError = () => {printInfo('server started on port $port')};
    }

    if (onError == null) {
      onError = () => {printError('error stopping server')};
    }

    // request the OS to bind a new socket to the specified port
    Future<ServerSocket> serverFuture = ServerSocket.bind('0.0.0.0', port);

    serverFuture.then((ServerSocket server) {

      mainSocket = server;

      // listen for incomming connections
      mainSocket.listen((Socket socket) {

        bool granted = false;
        Socket remoteSocket = null;

        // listen for incoming data
        socket.listen((List<int> data) {

          printDebug('incoming ${data.length} bytes from client host');

          if (granted) {
            printDebug('already granted, retransmitting data to remote host');
            remoteSocket.add(data);

          } else {
            printInfo('new client');

            var req = parseSocksRequest(data);
            printDebug(req);

            if (req == null) {
              // invalid request
              var resp = buildRejectedResponse();
              socket.add(resp);
              printDebug('invalid request, closing connection');
              socket.close();

            } else {
              // valid request, open connection with remote host
              InternetAddress remoteHostAddr = InternetAddress(req['ip']);

              Socket.connect(remoteHostAddr, req['port']).then((Socket sock) {

                remoteSocket = sock;

                remoteSocket.listen((List<int> data) {
                  printDebug('received ${data.length} bytes from remote host, retransmiting to client host');
                  socket.add(data);
                }, onError: (error) => printError('error: $error'));

                remoteSocket.done.catchError((error) => printError('error: $error'));

                var resp = buildGrantedResponse();
                granted = true;
                socket.add(resp);

              });
            }

          }

        }, onError: (error) => printError('error: $error'));

        socket.done.catchError((error) => printError('error: $error'));
      }, onError: (error) => printError('error: $error'));

      onDone();

    }).catchError((error) => {onError()});

    return true;
  }

  bool stop({Function onDone, Function onError}) {

    if (onDone == null) {
      onError = () => {printInfo('server stopped')};
    }

    if (onError == null) {
      onError = () => {printError('error stopping server')};
    }

    mainSocket.close()
      .then((socket) => {onDone()})
      .catchError((error) => {onError()});
  }
}


void main() async {

  var server = new DartSocks4();

  server.start(9090, onDone: () => {print('abriendo el garito!')});

  // // wait 5 seconds
  // await new Future.delayed(const Duration(seconds : 5));

  // server.stop(onDone: () => {print('cerrando el garito...')});

}
