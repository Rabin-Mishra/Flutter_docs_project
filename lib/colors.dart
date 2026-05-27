import 'package:flutter/material.dart';

const kWhiteColor = Colors.white;
const kBlackColor = Colors.black;
const kRedColor = Colors.red;
const kBlueColor = Color.fromRGBO(26, 115, 232, 1);
var kGreyColor = Colors.grey.shade800;

Color getUserColor(String email) {
  final colors = [
    const Color(0xFF1A73E8), // Google Blue
    const Color(0xFFD93025), // Google Red
    const Color(0xFFF9AB00), // Google Yellow
    const Color(0xFF188038), // Google Green
    const Color(0xFFE2725B), // Terracotta
    const Color(0xFF00ACC1), // Cyan
    const Color(0xFF8E24AA), // Purple
    const Color(0xFFD81B60), // Pink
    const Color(0xFF00897B), // Teal
    const Color(0xFFF4511E), // Deep Orange
  ];
  
  if (email.isEmpty) return colors[0];
  
  int hash = 0;
  for (int i = 0; i < email.length; i++) {
    hash = email.codeUnitAt(i) + ((hash << 5) - hash);
  }
  
  return colors[hash.abs() % colors.length];
}
