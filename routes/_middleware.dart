// routes/_middleware.dart
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_cors/dart_frog_cors.dart';

Handler middleware(Handler handler) {
  return handler.use(cors());
}
