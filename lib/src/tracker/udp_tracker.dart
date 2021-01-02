import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:dartorrent_common/dartorrent_common.dart';

import 'peer_event.dart';

import 'udp_tracker_base.dart';
import '../utils.dart';

import 'tracker.dart';

/// UDP Tracker
class UDPTracker extends Tracker with UDPTrackerBase {
  String _currentEvent;
  UDPTracker(Uri _uri, Uint8List infoHashBuffer,
      {AnnounceOptionsProvider provider})
      : super('udp:${_uri.host}:${_uri.port}', _uri, infoHashBuffer,
            provider: provider);

  String get currentEvent {
    return _currentEvent;
  }

  @override
  Uri get uri => announceUrl;

  @override
  Future<PeerEvent> announce(String eventType, Map<String, dynamic> options) {
    _currentEvent = eventType;
    return contactAnnouncer<PeerEvent>(options);
  }

  @override
  Uint8List generateSecondTouchMessage(Uint8List connectionId, Map options) {
    var list = <int>[];
    list.addAll(connectionId);
    list.addAll(ACTION_ANNOUNCE); // Action的类型，目前是announce,即1
    list.addAll(transcationId); // 会话ID
    list.addAll(infoHashBuffer);
    list.addAll(utf8.encode(options['peerId']));
    list.addAll(num2Uint64List(options['downloaded']));
    list.addAll(num2Uint64List(options['left']));
    list.addAll(num2Uint64List(options['uploaded']));
    var event = EVENTS[currentEvent];
    event ??= 0;
    list.addAll(num2Uint32List(event)); // 这里是event类型
    list.addAll(num2Uint32List(0)); // 这里是ip地址，默认0
    list.addAll(num2Uint32List(0)); // 这里是keym,默认0
    list.addAll(num2Uint32List(options['numwant'])); // 这里是num_want,默认-1
    list.addAll(num2Uint16List(options['port'])); // 这里是TCP的端口
    return Uint8List.fromList(list);
  }

  @override
  dynamic processResponseData(Uint8List data, int action) {
    if (data.length < 20) {
      // 数据不正确
      throw Exception('announce data is wrong');
    }
    var view = ByteData.view(data.buffer);
    var event = PeerEvent(infoHash, uri,
        interval: view.getUint32(8),
        incomplete: view.getUint32(16),
        complete: view.getUint32(12));
    var ips = data.sublist(20);
    try {
      var list = CompactAddress.parseIPv4Addresses(ips);
      list?.forEach((c) {
        event.addPeer(c);
      });
    } catch (e) {
      // 容错
      log('解析peer ip 出错 : $ips , ${ips.length}',
          name: runtimeType.toString(), error: e);
    }
    return event;
  }

  @override
  Future dispose([dynamic reason]) {
    close();
    return super.dispose(reason);
  }

  @override
  void handleSocketDone() {
    dispose('远程/本地 关闭了连接');
  }

  @override
  void handleSocketError(e) {
    dispose(e);
  }
}
