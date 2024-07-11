import 'dart:async';

import 'package:phoenix_wings_allow_any/src/phoenix_channel.dart';
import 'package:phoenix_wings_allow_any/src/phoenix_message.dart';

class PhoenixPush {
  bool sent = false;
  Map? receivedResp;
  int? timeout;
  List recHooks = [];
  Map? payload = {};
  dynamic payloadAny = "";
  PhoenixChannel? channel;
  String? event;
  String? ref;
  String? refEvent;

  Timer? timeoutTimer;

  PhoenixPush(this.channel, this.event, this.payload, this.timeout) {
    ref = this.channel!.socket!.makeRef();
  }

  PhoenixPush.fromPush(PhoenixPush push, dynamic anyPayload) {
    ref = push.ref;
    channel = push.channel;
    event = push.event;
    payloadAny = anyPayload;
    timeout = push.timeout;
  }

  PhoenixPush receiveAny(Function(Map? response) callback) {
    print('PhoenixPush receive any');
    callback(receivedResp);
    final status = getReceiveStatus();
    if (status != null) {
      this.recHooks.add(new _PhoenixPushStatus(status, callback));
    }
    return this;
  }

  PhoenixPush receive(String status, Function(Map? response) callback) {
    print('PhoenixPush receive status = $status, event = $event, channel = ${channel?.topic}');
    if (hasReceived(status)) {
      callback(receivedResp);
    }

    this.recHooks.add(new _PhoenixPushStatus(status, callback));
    return this;
  }
  
  String? getReceiveStatus() {
    if (receivedResp != null) {
      final status = receivedResp!["status"];
      if (status != null && status is String) {
        return status;
      }
      return null;
    }
  }

  bool hasReceived(status) {
    return receivedResp != null && receivedResp!["status"] == status;
  }

  matchReceive(Map? payload) {
    recHooks
        .where((hook) => hook.status == payload!["status"])
        .forEach((hook) => hook.callback(payload!["response"]));
  }

  resend(int? timeout) {
    timeout = timeout;
    reset();
    send();
  }

  cancelRefEvent() {
    if (refEvent == null) {
      return;
    }
    channel!.off(refEvent);
  }

  reset() {
    cancelRefEvent();
    ref = null;
    refEvent = null;
    receivedResp = null;
    sent = false;
  }

  send() {
    startTimeout();
    refEvent = channel!.replyEventName(ref);
    sent = true;
    channel!.socket!.push(new PhoenixMessage(
        channel!.joinRef, ref, channel!.topic, event, payload));
  }

  sendAny() {
    startTimeout();
    refEvent = channel!.replyEventName(ref);
    sent = true;
    final message = PhoenixMessage(channel!.joinRef, ref, channel!.topic, event, payload);
    final messageAny = PhoenixMessage.fromMessage(message, payloadAny);
    channel!.socket!.push(messageAny);
  }

  startTimeout() {
    cancelTimeout();
    ref = channel!.socket!.makeRef();
    refEvent = channel!.replyEventName(ref);
    channel!.on(refEvent, (payload, _a, _b) {
      cancelRefEvent();
      cancelTimeout();
      receivedResp = payload;
      matchReceive(payload);
    });

    timeoutTimer = new Timer(new Duration(milliseconds: timeout!), () {
      trigger("timeout", {});
    });
  }

  cancelTimeout() {
    timeoutTimer?.cancel();
    timeoutTimer = null;
  }

  trigger(status, response) {
    channel!.trigger(refEvent, {"status": status, "response": response});
  }
}

class _PhoenixPushStatus {
  final status;
  final callback;
  _PhoenixPushStatus(this.status, this.callback);
}
