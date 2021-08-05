import 'package:firebase_auth/firebase_auth.dart';
import 'package:rider_app/Models/allUsers.dart';

String mapKey = "AIzaSyALtrp31ibvr57p_QPRRV4Dv1qV-MxU5QM";

User? firebaseUser;

Users? userCurrentInfo;
int driverRequestTimeOut = 40;
String statusRide = "";
String rideStatus = "Driver is Coming...";
String carDetailsDriver = "";
String driverName = "";
String driverPhone = "";

double starCounter = 0.0;
String title = "";
String carRideType = "";

String serverToken =
    "key=AAAAAkLowNY:APA91bEf-SnBN5umAXGb6OrxO9nGI7cucO3adT2ri_r4aut1fRYzdXD4dSxF-GNT5uHWMkuo_xdmeujamkLlvS-yEede6gLYFEprZg44ieNCilVbMpNgdXWBDl1NeB_nuyWoEXiHh-zm";
