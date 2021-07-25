import 'dart:ffi';

import 'package:flutter/cupertino.dart';
import 'package:rider_app/Models/address.dart';

class AppData extends ChangeNotifier {
  Address? pickUpLocation;

  void updatePickUpLocationAddress(Address pickUpAddress) async {
    pickUpLocation = pickUpAddress;
    notifyListeners();
  }
}
