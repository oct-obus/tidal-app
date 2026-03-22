import 'package:flutter/services.dart';

const pythonChannel = MethodChannel('com.obus.tidal_app/python');
const audioChannel = MethodChannel('com.obus.tidal_app/audio');

const kPlayerPollInterval = Duration(milliseconds: 500);
const kDownloadPollInterval = Duration(milliseconds: 500);
