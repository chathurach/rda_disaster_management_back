import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:dio/dio.dart' as dio;
import 'package:rda_disaster_management/kmz_processor.dart'; // Aliased Dio to prevent conflict with dart_frog.Response

// IMPORTANT: Replace this with the Web App URL copied from Google Apps Script deployment (Step 3).
const _googleSheetApiUrl =
    'https://script.google.com/macros/s/AKfycbypl0TLIj2nFkLaI06JWDUsgr65B_LS4-hwlqVby_gpnqAHMflPQrP3T72VznTDLQYwUA/exec';

// Initialize Dio client once
final _dio = dio.Dio();

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: 405,
      body: {'message': 'Method Not Allowed'},
    );
  }

  try {
    // 1. Make the GET request to the Google Apps Script Web App using Dio
    final response = await _dio.get(_googleSheetApiUrl);

    if (response.statusCode == 200) {
      final jsonResponse = response.data;

      // Check for the Google Sheet API's expected 'data' key and 'status'
      if (jsonResponse is Map &&
          jsonResponse['status'] == 'success' &&
          jsonResponse['data'] is List) {
        // 2. Process the raw data to find the Lat/Lon coordinates using the KMZ processor
        final processedData = processSheetData(jsonResponse['data'] as List);

        // 3. Return the augmented data list
        return Response.json(
          statusCode: 200,
          body: {
            'status': 'success',
            'data': processedData, // This now contains Lat/Lon fields
          },
        );
      } else if (jsonResponse is Map && jsonResponse.containsKey('error')) {
        // 3. Handle a potential custom error message defined in the Apps Script
        return Response.json(
          statusCode: 500,
          body: {
            'error': 'Sheet Script Error',
            'details': jsonResponse['error']
          },
        );
      }

      // Fallback for unexpected successful response structure
      return Response.json(
        statusCode: 500,
        body: {'error': 'Unexpected response structure from Google Sheet API.'},
      );
    }
  } on dio.DioException catch (e) {
    // DioException handles network errors and non-2xx status codes automatically
    if (e.response != null) {
      // The request was made and the server responded with a status code
      // that falls out of the range of 2xx.
      return Response.json(
        statusCode: e.response!.statusCode ?? 500,
        body: {
          'error': 'API request failed.',
          'details': e.toString(),
          'data': e.response?.data
        },
      );
    } else {
      // Something happened in setting up or sending the request that triggered an Error
      return Response.json(
        statusCode: 500,
        body: {
          'error': 'Network or request setup error.',
          'details': e.toString()
        },
      );
    }
  } catch (e) {
    // Catch any other unexpected exceptions
    return Response.json(
      statusCode: 500,
      body: {'error': 'An unexpected error occurred.', 'details': e.toString()},
    );
  }

  // Should be unreachable if try/catch blocks cover all return paths
  return Response(statusCode: 500, body: 'Unknown Error');
}
