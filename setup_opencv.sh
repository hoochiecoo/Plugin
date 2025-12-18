#!/bin/bash
set -e

PLUGIN_NAME=opencv_native

echo "Creating Flutter FFI plugin..."
flutter create --template=plugin_ffi --platforms=android,ios $PLUGIN_NAME

echo "Adding native C++ file..."
mkdir -p $PLUGIN_NAME/android/src/main/cpp

cat <<EOF > $PLUGIN_NAME/android/src/main/cpp/native_lib.cpp
#include <jni.h>
#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>

extern "C" JNIEXPORT jint JNICALL
Java_com_example_opencv_1native_NativeLib_getImageWidth(JNIEnv*, jobject, jstring path) {
    const char* filePath = reinterpret_cast<const char*>(path);
    cv::Mat img = cv::imread(filePath, cv::IMREAD_COLOR);
    if (img.empty()) return -1;
    return img.cols;
}
EOF

cat <<EOF > $PLUGIN_NAME/android/src/main/cpp/CMakeLists.txt
cmake_minimum_required(VERSION 3.4.1)

add_library(native_lib SHARED native_lib.cpp)

find_package(OpenCV REQUIRED core imgcodecs)

target_include_directories(native_lib PRIVATE \${OpenCV_INCLUDE_DIRS})
target_link_libraries(native_lib \${OpenCV_LIBS} log)
EOF

echo "Adding Dart FFI wrapper..."
cat <<EOF > $PLUGIN_NAME/lib/opencv_native.dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef c_getImageWidth_func = Int32 Function(Pointer<Utf8>);
typedef dart_getImageWidth_func = int Function(Pointer<Utf8>);

class NativeLib {
  late DynamicLibrary _lib;

  NativeLib() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libnative_lib.so');
    } else if (Platform.isIOS) {
      _lib = DynamicLibrary.process();
    }
  }

  int getImageWidth(String path) {
    final func = _lib.lookupFunction<c_getImageWidth_func, dart_getImageWidth_func>('Java_com_example_opencv_1native_NativeLib_getImageWidth');
    final ptr = path.toNativeUtf8();
    final result = func(ptr);
    malloc.free(ptr);
    return result;
  }
}
EOF

echo "Updating example main.dart..."
cat <<EOF > $PLUGIN_NAME/example/lib/main.dart
import 'package:flutter/material.dart';
import 'package:opencv_native/opencv_native.dart';

void main() {
  final lib = NativeLib();

  int width = lib.getImageWidth("/sdcard/test.jpg");
  print('Image width: \$width');

  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Image width: \$width')),
      ),
    ),
  );
}
EOF

echo "Getting Flutter packages..."
cd $PLUGIN_NAME/example
flutter pub get

echo "Building debug APK..."
flutter build apk --debug

echo "APK built at: $PLUGIN_NAME/example/build/app/outputs/flutter-apk/app-debug.apk"
