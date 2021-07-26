import 'dart:ffi';

import 'package:flutter/cupertino.dart';
import 'package:rider_app/Models/address.dart';

class AppData extends ChangeNotifier {
  Address? pickUpLocation, dropOffLocation;

  void updatePickUpLocationAddress(Address pickUpAddress) async {
    pickUpLocation = pickUpAddress;
    notifyListeners();
  }

  void updateDropOffLocationAddress(Address dropOffAddress) async {
    dropOffLocation = dropOffAddress;
    notifyListeners();
  }
}
