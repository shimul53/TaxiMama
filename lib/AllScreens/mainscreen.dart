import 'dart:async';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_geofire/flutter_geofire.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:rider_app/AllScreens/loginScreen.dart';
import 'package:rider_app/AllScreens/ratingScreen.dart';
import 'package:rider_app/AllScreens/registrationScreen.dart';
import 'package:rider_app/AllScreens/searchScreen.dart';
import 'package:rider_app/AllWidgets/CollectFareDialog.dart';
import 'package:rider_app/AllWidgets/Divider.dart';
import 'package:rider_app/AllWidgets/noDriverAvailableDialog.dart';
import 'package:rider_app/AllWidgets/progressDialog.dart';
import 'package:rider_app/Assistants/assistantMethods.dart';
import 'package:rider_app/Assistants/geoFireAssistant.dart';
import 'package:rider_app/DataHandler/appData.dart';
import 'package:rider_app/Models/address.dart';
import 'package:rider_app/Models/directDetails.dart';
import 'package:rider_app/Models/nearbyAvailableDrivers.dart';
import 'package:rider_app/configMaps.dart';
import 'package:rider_app/main.dart';
import 'package:url_launcher/url_launcher.dart';

class MainScreen extends StatefulWidget {
  static const String idScreen = "mainScreen";

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  Completer<GoogleMapController> _controllerGoogleMap = Completer();
  late GoogleMapController newGoogleMapController;

  GlobalKey<ScaffoldState> scaffoldKey = new GlobalKey<ScaffoldState>();
  DirectionDetails? tripDirectionDetails;

  List<LatLng> pLineCoordinates = [];
  Set<Polyline> polylineSet = {};
  late Position currentPosition;
  var geoLocator = Geolocator();
  double bottomPaddingOfMap = 0;

  Set<Marker> markersSet = {};
  Set<Circle> circlesSet = {};

  double rideDetailsContainerHeight = 0;
  double requestRideDetailsContainerHeight = 0;
  double searchContainerHeight = 300.0;
  double driverDetailsContainerHeight = 0;

  bool drawerOpen = true;
  bool nearbyAvailableDriverKeysLoaded = false;

  DatabaseReference? rideRequestRef;

  BitmapDescriptor? nearbyIcon;

  List<NearbyAvailableDrivers>? availableDrivers;
  String state = "normal";

  StreamSubscription<Event>? rideStreamSubscription;
  bool isRequestingPositionDetails = false;

  String uName = "";

  @override
  void initState() {
    super.initState();
    AssistantMethods.getCurrentOnlineUserInfo();
  }

  void saveRideRequest() {
    rideRequestRef =
        FirebaseDatabase.instance.reference().child("Ride Requests").push();
    var pickUp = Provider.of<AppData>(context, listen: false).pickUpLocation;
    var dropOff = Provider.of<AppData>(context, listen: false).dropOffLocation;

    Map pickUpLocMap = {
      "latitude": pickUp!.latitude.toString(),
      "longitude": pickUp.longitude.toString(),
    };

    Map dropOffLocMap = {
      "latitude": dropOff!.latitude.toString(),
      "longitude": dropOff.longitude.toString(),
    };

    Map rideInfoMap = {
      "driver_id": "waiting",
      "payment_method": "cash",
      "pickup": pickUpLocMap,
      "dropoff": dropOffLocMap,
      "created_at": DateTime.now().toString(),
      "rider_name": userCurrentInfo!.name,
      "rider_phone": userCurrentInfo!.phone,
      "pickup_address": pickUp.placeName,
      "dropoff_address": dropOff.placeName,
      "ride_type": carRideType,
    };
    rideRequestRef!.set(rideInfoMap);
    rideStreamSubscription = rideRequestRef!.onValue.listen((event) async {
      if (event.snapshot.value == null) {
        return;
      }

      if (event.snapshot.value["car_details"] != null) {
        setState(() {
          carDetailsDriver = event.snapshot.value["car_details"].toString();
        });
      }

      if (event.snapshot.value["driver_name"] != null) {
        setState(() {
          driverName = event.snapshot.value["driver_name"].toString();
        });
      }
      if (event.snapshot.value["driver_phone"] != null) {
        setState(() {
          driverPhone = event.snapshot.value["driver_phone"].toString();
        });
      }
      if (event.snapshot.value["driver_location"] != null) {
        double driverLat = double.parse(
            event.snapshot.value["driver_location"]["latitude"].toString());
        double driverLng = double.parse(
            event.snapshot.value["driver_location"]["longitude"].toString());
        LatLng driverCurrentLocation = LatLng(driverLat, driverLng);
        if (statusRide == "accepted") {
          updateRideTimeToPickUpLoc(driverCurrentLocation);
        } else if (statusRide == "onride") {
          updateRideTimeToDropOffLoc(driverCurrentLocation);
        } else if (statusRide == "arrived") {
          setState(() {
            rideStatus = "Driver has Arrived.";
          });
        }
      }
      if (event.snapshot.value["status"] != null) {
        statusRide = event.snapshot.value["status"].toString();
      }
      if (statusRide == "accepted") {
        displayDriverDetailsContainer();
        Geofire.stopListener();
        deleteGeoFireMarkers();
      }

      if (statusRide == "ended") {
        if (event.snapshot.value["fares"] != null) {
          int fare = int.parse(event.snapshot.value["fares"].toString());
          var res = await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) => CollectFareDialog(
              paymentMethod: "cash",
              fareAmount: fare,
            ),
          );
          String driverId = "";
          if (res == "close") {
            if (event.snapshot.value["driver_id"] != null) {
              driverId = event.snapshot.value["driver_id"].toString();
            }
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => RatingScreen(driverId: driverId)));
            rideRequestRef!.onDisconnect();
            rideRequestRef = null;
            rideStreamSubscription!.cancel();
            rideStreamSubscription = null;
            resetApp();
          }
        }
      }
    });
  }

  void deleteGeoFireMarkers() {
    setState(() {
      markersSet
          .removeWhere((element) => element.markerId.value.contains("driver"));
    });
  }

  void updateRideTimeToPickUpLoc(LatLng driverCurrentLatitude) async {
    if (isRequestingPositionDetails == false) {
      isRequestingPositionDetails = true;
      var positionUserLatLng =
          LatLng(currentPosition.latitude, currentPosition.longitude);
      var details = await AssistantMethods.obtainPlaceDirectionDetails(
          driverCurrentLatitude, positionUserLatLng);
      if (details == null) {
        return;
      }
      setState(() {
        rideStatus = "Driver is Coming -" + details.durationText.toString();
      });
      isRequestingPositionDetails = false;
    }
  }

  void updateRideTimeToDropOffLoc(LatLng driverCurrentLatitude) async {
    if (isRequestingPositionDetails == false) {
      isRequestingPositionDetails = true;
      var dropOff =
          Provider.of<AppData>(context, listen: false).dropOffLocation;
      var dropOffUserLatLng = LatLng(dropOff!.latitude, dropOff!.longitude);
      var details = await AssistantMethods.obtainPlaceDirectionDetails(
          driverCurrentLatitude, dropOffUserLatLng);
      if (details == null) {
        return;
      }
      setState(() {
        rideStatus = "Going to Destination-" + details.durationText.toString();
      });
      isRequestingPositionDetails = false;
    }
  }

  void cancelRideRequest() {
    rideRequestRef!.remove();
    setState(() {
      state = "normal";
    });
  }

  void displayRequestRideContainer() {
    setState(() {
      requestRideDetailsContainerHeight = 250.0;
      rideDetailsContainerHeight = 0;
      bottomPaddingOfMap = 270.0;
      drawerOpen = true;
    });
    saveRideRequest();
  }

  static const colorizeColors = [
    Colors.green,
    Colors.purple,
    Colors.pink,
    Colors.blue,
    Colors.yellow,
    Colors.red,
  ];

  static const colorizeTextStyle = TextStyle(
    fontSize: 55.0,
    fontFamily: 'Signatra',
  );

  void displayRideDetailsContainer() async {
    await getPlaceDirection();
    setState(() {
      searchContainerHeight = 0;
      rideDetailsContainerHeight = 350.0;
      bottomPaddingOfMap = 370.0;
      drawerOpen = false;
    });
    saveRideRequest();
  }

  void displayDriverDetailsContainer() {
    setState(() {
      rideDetailsContainerHeight = 0.0;
      requestRideDetailsContainerHeight = 0.0;
      bottomPaddingOfMap = 280.0;
      driverDetailsContainerHeight = 310.0;
    });
  }

  resetApp() {
    setState(() {
      drawerOpen = true;
      searchContainerHeight = 300.0;
      rideDetailsContainerHeight = 0;
      requestRideDetailsContainerHeight = 0;
      bottomPaddingOfMap = 230.0;
      polylineSet.clear();
      markersSet.clear();
      circlesSet.clear();
      pLineCoordinates.clear();

      statusRide = "";
      driverName = "";
      driverPhone = "";
      carDetailsDriver = "";
      rideStatus = "Driver is Coming...";
      driverDetailsContainerHeight = 0.0;
    });
    locatePosition();
  }

  void locatePosition() async {
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    currentPosition = position;
    LatLng latLonPosition = LatLng(position.latitude, position.longitude);
    CameraPosition cameraPosition =
        new CameraPosition(target: latLonPosition, zoom: 14);
    newGoogleMapController
        .animateCamera(CameraUpdate.newCameraPosition(cameraPosition));
    String address =
        await AssistantMethods.searchCoordinateAddress(position, context);
    print("This is your Address ::" + address);
    initGeoFireListener();
    uName = userCurrentInfo!.name.toString();
  }

  static final CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962),
    zoom: 14.4746,
  );

  @override
  Widget build(BuildContext context) {
    createIconMarker();
    return Scaffold(
      key: scaffoldKey,
      drawer: Container(
        color: Colors.black,
        width: 255.0,
        child: Drawer(
          child: ListView(
            children: [
              Container(
                height: 165.0,
                child: DrawerHeader(
                  decoration: BoxDecoration(color: Colors.white),
                  child: Row(
                    children: [
                      Image.asset(
                        "images/user_icon.png",
                        height: 65.0,
                        width: 65.0,
                      ),
                      SizedBox(
                        width: 16.0,
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            uName,
                            style: TextStyle(
                                fontSize: 16.0,
                                fontFamily: "Brand Bold",
                                color: Colors.black),
                          ),
                          SizedBox(
                            height: 6.0,
                          ),
                          Text("Visit Profile"),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              DividerWidget(),
              SizedBox(
                height: 12.0,
              ),
              ListTile(
                leading: Icon(Icons.history),
                title: Text(
                  "History",
                  style: TextStyle(fontSize: 15.0),
                ),
              ),
              ListTile(
                leading: Icon(Icons.person),
                title: Text(
                  "Visit Profile",
                  style: TextStyle(fontSize: 15.0),
                ),
              ),
              ListTile(
                leading: Icon(Icons.info),
                title: Text(
                  "About",
                  style: TextStyle(fontSize: 15.0),
                ),
              ),
              GestureDetector(
                onTap: () {
                  FirebaseAuth.instance.signOut();
                  Navigator.pushNamedAndRemoveUntil(
                      context, LoginScreen.idScreen, (route) => false);
                },
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text(
                    "Sign Out",
                    style: TextStyle(fontSize: 15.0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(children: [
        GoogleMap(
          padding: EdgeInsets.only(bottom: bottomPaddingOfMap, top: 50.0),
          mapType: MapType.normal,
          initialCameraPosition: _kGooglePlex,
          myLocationEnabled: true,
          zoomGesturesEnabled: true,
          zoomControlsEnabled: true,
          myLocationButtonEnabled: true,
          polylines: polylineSet,
          markers: markersSet,
          circles: circlesSet,
          onMapCreated: (GoogleMapController controller) {
            _controllerGoogleMap.complete(controller);
            newGoogleMapController = controller;

            setState(() {
              bottomPaddingOfMap = 300.0;
            });

            locatePosition();
          },
        ),
        //HamburgerButton for Drawer
        Positioned(
          top: 70.0,
          left: 22.0,
          child: GestureDetector(
            onTap: () {
              if (drawerOpen) {
                scaffoldKey.currentState!.openDrawer();
              } else {
                resetApp();
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(22.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black,
                    blurRadius: 6.0,
                    spreadRadius: 0.5,
                    offset: Offset(
                      0.7,
                      0.7,
                    ),
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundColor: Colors.yellowAccent,
                child: Icon(
                  (drawerOpen) ? Icons.menu : Icons.close,
                  color: Colors.black,
                ),
                radius: 20.0,
              ),
            ),
          ),
        ),

        //Search UI
        Positioned(
            left: 0.0,
            right: 0.0,
            bottom: 0.0,
            child: AnimatedSize(
              vsync: this,
              curve: Curves.bounceIn,
              duration: new Duration(milliseconds: 160),
              child: Container(
                height: searchContainerHeight,
                decoration: BoxDecoration(
                  color: Colors.yellowAccent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18.0),
                    topRight: Radius.circular(18.0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black,
                      blurRadius: 16.0,
                      spreadRadius: 0.5,
                      offset: Offset(0.7, 0.7),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 6.0,
                      ),
                      Text(
                        "Hi there,",
                        style: TextStyle(fontSize: 12.0),
                      ),
                      Text(
                        "Where to?",
                        style: TextStyle(
                          fontSize: 20.0,
                          fontFamily: "Brand Bold",
                        ),
                      ),
                      SizedBox(
                        height: 20.0,
                      ),
                      GestureDetector(
                        onTap: () async {
                          var res = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => SearchScreen()));
                          if (res == "obtainDirection") {
                            displayRideDetailsContainer();
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(5.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 6.0,
                                spreadRadius: 0.5,
                                offset: Offset(0.7, 0.7),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search,
                                  color: Colors.black,
                                ),
                                SizedBox(
                                  width: 10.0,
                                ),
                                Text("Search drop off ")
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 24.0,
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.home,
                            color: Colors.black,
                          ),
                          SizedBox(
                            width: 12.0,
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ignore: unnecessary_null_comparison

                              Text(
                                Provider.of<AppData>(context).pickUpLocation !=
                                        null
                                    ? Provider.of<AppData>(context)
                                        .pickUpLocation!
                                        .placeName
                                        .toString()
                                    : "Add Home",
                                style: TextStyle(fontFamily: "Brand Bold"),
                              ),
                              SizedBox(
                                height: 4.0,
                              ),
                              Text(
                                "Your living home address",
                                style: TextStyle(
                                    color: Colors.black54, fontSize: 12.0),
                              ),
                            ],
                          )
                        ],
                      ),
                      SizedBox(
                        height: 10.0,
                      ),
                      DividerWidget(),
                      SizedBox(
                        height: 16.0,
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.work,
                            color: Colors.black,
                          ),
                          SizedBox(
                            width: 12.0,
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Add Work",
                                style: TextStyle(fontFamily: "Brand Bold"),
                              ),
                              SizedBox(
                                height: 4.0,
                              ),
                              Text(
                                "Your office address",
                                style: TextStyle(
                                    color: Colors.black54, fontSize: 12.0),
                              ),
                            ],
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )),

        //Ride Details UI
        Positioned(
          bottom: 0.0,
          left: 0.0,
          right: 0.0,
          child: AnimatedSize(
            vsync: this,
            curve: Curves.bounceIn,
            duration: new Duration(milliseconds: 160),
            child: Container(
              height: rideDetailsContainerHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16.0),
                  topRight: Radius.circular(16.0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black,
                    blurRadius: 16.0,
                    spreadRadius: 0.5,
                    offset: Offset(0.7, 0.7),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 17.0),
                child: Column(
                  children: [
                    //bike ride
                    GestureDetector(
                      onTap: () {
                        displayToastMessage("Searching Bike...", context);
                        setState(() {
                          state = "requesting";
                          carRideType = "bike";
                        });
                        displayRequestRideContainer();
                        availableDrivers =
                            GeoFireAssistant.nearbyAvailableDriversList;
                        searchNearestDriver();
                      },
                      child: Container(
                        width: double.infinity,
                        color: Colors.tealAccent[100],
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            children: [
                              Image.asset(
                                "images/bike.png",
                                height: 70.0,
                                width: 80.0,
                              ),
                              SizedBox(
                                width: 16.0,
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Bike",
                                    style: TextStyle(
                                      fontSize: 18.0,
                                      fontFamily: "Brand Bold",
                                    ),
                                  ),
                                  Text(
                                    ((tripDirectionDetails != null)
                                        ? tripDirectionDetails!.distanceText
                                            .toString()
                                        : ''),
                                    style: TextStyle(
                                      fontSize: 16.0,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              Expanded(child: Container()),
                              Text(
                                ((tripDirectionDetails != null)
                                    ? "Tk ${(AssistantMethods.calculateFares(tripDirectionDetails!)) / 2}"
                                    : ''),
                                style: TextStyle(
                                  fontFamily: "Brand Bold",
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SizedBox(
                      height: 10.0,
                    ),
                    Divider(
                      height: 2.0,
                      thickness: 2.0,
                    ),
                    SizedBox(
                      height: 10.0,
                    ),

                    //uber-go ride
                    GestureDetector(
                      onTap: () {
                        displayToastMessage("Searching Uber-Go", context);
                        setState(() {
                          state = "requesting";
                          carRideType = "uber-go";
                        });
                        displayRequestRideContainer();
                        availableDrivers =
                            GeoFireAssistant.nearbyAvailableDriversList;
                        searchNearestDriver();
                      },
                      child: Container(
                        width: double.infinity,
                        color: Colors.tealAccent[100],
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            children: [
                              Image.asset(
                                "images/ubergo.png",
                                height: 70.0,
                                width: 80.0,
                              ),
                              SizedBox(
                                width: 16.0,
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Uber-Go",
                                    style: TextStyle(
                                      fontSize: 18.0,
                                      fontFamily: "Brand Bold",
                                    ),
                                  ),
                                  Text(
                                    ((tripDirectionDetails != null)
                                        ? tripDirectionDetails!.distanceText
                                            .toString()
                                        : ''),
                                    style: TextStyle(
                                      fontSize: 16.0,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              Expanded(child: Container()),
                              Text(
                                ((tripDirectionDetails != null)
                                    ? "Tk ${AssistantMethods.calculateFares(tripDirectionDetails!)}"
                                    : ''),
                                style: TextStyle(
                                  fontFamily: "Brand Bold",
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SizedBox(
                      height: 10.0,
                    ),
                    Divider(
                      height: 2.0,
                      thickness: 2.0,
                    ),
                    SizedBox(
                      height: 10.0,
                    ),

                    //uber-x ride
                    GestureDetector(
                      onTap: () {
                        displayToastMessage("Searching Uber-X", context);
                        setState(() {
                          state = "requesting";
                          carRideType = "uber-x";
                        });
                        displayRequestRideContainer();
                        availableDrivers =
                            GeoFireAssistant.nearbyAvailableDriversList;
                        searchNearestDriver();
                      },
                      child: Container(
                        width: double.infinity,
                        color: Colors.tealAccent[100],
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            children: [
                              Image.asset(
                                "images/uberx.png",
                                height: 70.0,
                                width: 80.0,
                              ),
                              SizedBox(
                                width: 16.0,
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Uber-X",
                                    style: TextStyle(
                                      fontSize: 18.0,
                                      fontFamily: "Brand Bold",
                                    ),
                                  ),
                                  Text(
                                    ((tripDirectionDetails != null)
                                        ? tripDirectionDetails!.distanceText
                                            .toString()
                                        : ''),
                                    style: TextStyle(
                                      fontSize: 16.0,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              Expanded(child: Container()),
                              Text(
                                ((tripDirectionDetails != null)
                                    ? "Tk ${(AssistantMethods.calculateFares(tripDirectionDetails!)) * 2}"
                                    : ''),
                                style: TextStyle(
                                  fontFamily: "Brand Bold",
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SizedBox(
                      height: 10.0,
                    ),
                    Divider(
                      height: 2.0,
                      thickness: 2.0,
                    ),
                    SizedBox(
                      height: 10.0,
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.0),
                      child: Row(
                        children: [
                          Icon(
                            FontAwesomeIcons.moneyCheckAlt,
                            size: 18.0,
                            color: Colors.black54,
                          ),
                          SizedBox(
                            width: 16.0,
                          ),
                          Text("Cash"),
                          SizedBox(
                            width: 6.0,
                          ),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 16.0,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        //Request Or Cancel UI
        Positioned(
          bottom: 0.0,
          left: 0.0,
          right: 0.0,
          child: Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16.0),
                  topRight: Radius.circular(16.0),
                ),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    spreadRadius: 0.5,
                    blurRadius: 16.0,
                    color: Colors.black54,
                    offset: Offset(0.7, 0.7),
                  )
                ]),
            height: requestRideDetailsContainerHeight,
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                children: [
                  SizedBox(
                    height: 12.0,
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedTextKit(
                      animatedTexts: [
                        ColorizeAnimatedText(
                          'Requesting a Ride...',
                          textStyle: colorizeTextStyle,
                          colors: colorizeColors,
                          textAlign: TextAlign.center,
                        ),
                        ColorizeAnimatedText(
                          'Please wait...',
                          textStyle: colorizeTextStyle,
                          colors: colorizeColors,
                          textAlign: TextAlign.center,
                        ),
                        ColorizeAnimatedText(
                          'Finding a Driver...',
                          textStyle: colorizeTextStyle,
                          colors: colorizeColors,
                          textAlign: TextAlign.center,
                        ),
                      ],
                      isRepeatingAnimation: true,
                      onTap: () {
                        print("Tap Event");
                      },
                    ),
                  ),
                  SizedBox(
                    height: 22.0,
                  ),
                  GestureDetector(
                    onTap: () {
                      cancelRideRequest();
                      resetApp();
                    },
                    child: Container(
                      height: 60.0,
                      width: 60.0,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26.0),
                          border: Border.all(width: 2.0, color: Colors.grey)),
                      child: Icon(
                        Icons.close,
                        size: 26.0,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 10.0,
                  ),
                  Container(
                    width: double.infinity,
                    child: Text(
                      "Cancel Ride",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        //Display assigned driver info
        Positioned(
          bottom: 0.0,
          left: 0.0,
          right: 0.0,
          child: Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16.0),
                  topRight: Radius.circular(16.0),
                ),
                color: Colors.yellowAccent,
                boxShadow: [
                  BoxShadow(
                    spreadRadius: 0.5,
                    blurRadius: 16.0,
                    color: Colors.black54,
                    offset: Offset(0.7, 0.7),
                  )
                ]),
            height: driverDetailsContainerHeight,
            child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 6.0,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          rideStatus,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20.0,
                            fontFamily: "Brand Bold",
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 22.0,
                    ),
                    Divider(
                      height: 2.0,
                      thickness: 2.0,
                    ),
                    SizedBox(
                      height: 22.0,
                    ),
                    Text(
                      carDetailsDriver,
                      style: TextStyle(color: Colors.black),
                    ),
                    Text(
                      driverName,
                      style:
                          TextStyle(fontSize: 20.0, fontFamily: "Brand Bold"),
                    ),
                    SizedBox(
                      height: 22.0,
                    ),
                    Divider(
                      height: 2.0,
                      thickness: 2.0,
                    ),
                    SizedBox(
                      height: 22.0,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        //call button
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20.0),
                          child: RaisedButton(
                            onPressed: () async {
                              launch(('tel://${driverPhone}'));
                            },
                            color: Colors.white,
                            child: Padding(
                              padding: EdgeInsets.all(17.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  Text(
                                    "Call Driver",
                                    style: TextStyle(
                                        fontSize: 20.0,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black),
                                  ),
                                  Icon(
                                    Icons.call,
                                    color: Colors.green,
                                    size: 26.0,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      ],
                    )
                  ],
                )),
          ),
        ),
      ]),
    );
  }

  Future<void> getPlaceDirection() async {
    var initialPos =
        Provider.of<AppData>(context, listen: false).pickUpLocation;
    var finalPos = Provider.of<AppData>(context, listen: false).dropOffLocation;

    var pickUpLatLng = LatLng(initialPos?.latitude, initialPos?.longitude);
    var dropOffLatLng = LatLng(finalPos?.latitude, finalPos?.longitude);

    showDialog(
        context: context,
        builder: (BuildContext context) => ProgressDialog(
              message: "Please wait...",
            ));
    var details = await AssistantMethods.obtainPlaceDirectionDetails(
        pickUpLatLng, dropOffLatLng);
    setState(() {
      tripDirectionDetails = details;
    });

    Navigator.pop(context);
    print("This is Encoded Points :: ");
    print(details!.encodedPoints);

    PolylinePoints polylinePoints = PolylinePoints();
    List<PointLatLng> decodedPolyLinePointsResult =
        polylinePoints.decodePolyline(details.encodedPoints);

    pLineCoordinates.clear();

    if (decodedPolyLinePointsResult.isNotEmpty) {
      decodedPolyLinePointsResult.forEach((PointLatLng pointLatLng) {
        pLineCoordinates
            .add(LatLng(pointLatLng.latitude, pointLatLng.longitude));
      });
    }
    polylineSet.clear();
    setState(() {
      Polyline polyline = Polyline(
        color: Colors.pink,
        polylineId: PolylineId("PolylineID"),
        jointType: JointType.round,
        points: pLineCoordinates,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: true,
      );
      polylineSet.add(polyline);
    });
    LatLngBounds latLngBounds;
    if (pickUpLatLng.latitude > dropOffLatLng.latitude &&
        pickUpLatLng.longitude > dropOffLatLng.longitude) {
      latLngBounds =
          LatLngBounds(southwest: dropOffLatLng, northeast: pickUpLatLng);
    } else if (pickUpLatLng.longitude > dropOffLatLng.longitude) {
      latLngBounds = LatLngBounds(
          southwest: LatLng(pickUpLatLng.latitude, dropOffLatLng.longitude),
          northeast: LatLng(dropOffLatLng.latitude, pickUpLatLng.longitude));
    } else if (pickUpLatLng.latitude > dropOffLatLng.latitude) {
      latLngBounds = LatLngBounds(
          southwest: LatLng(dropOffLatLng.latitude, pickUpLatLng.longitude),
          northeast: LatLng(pickUpLatLng.latitude, dropOffLatLng.longitude));
    } else {
      latLngBounds =
          LatLngBounds(southwest: pickUpLatLng, northeast: dropOffLatLng);
    }
    newGoogleMapController
        .animateCamera(CameraUpdate.newLatLngBounds(latLngBounds, 70));
    Marker pickUpLocMarker = Marker(
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      infoWindow:
          InfoWindow(title: initialPos?.placeName, snippet: "my location"),
      position: pickUpLatLng,
      markerId: MarkerId("pickUpId"),
    );

    Marker dropOffLocMarker = Marker(
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow:
          InfoWindow(title: finalPos?.placeName, snippet: "DropOff Location"),
      position: dropOffLatLng,
      markerId: MarkerId("dropOffId"),
    );
    setState(() {
      markersSet.add(pickUpLocMarker);
      markersSet.add(dropOffLocMarker);
    });

    Circle pickUpLocCircle = Circle(
      fillColor: Colors.black12,
      center: pickUpLatLng,
      radius: 12,
      strokeWidth: 4,
      strokeColor: Colors.black12,
      circleId: CircleId("pickUpId"),
    );

    Circle dropOffLocCircle = Circle(
      fillColor: Colors.black12,
      center: dropOffLatLng,
      radius: 12,
      strokeWidth: 4,
      strokeColor: Colors.black12,
      circleId: CircleId("dropOffId"),
    );
    setState(() {
      circlesSet.add(pickUpLocCircle);
      circlesSet.add(dropOffLocCircle);
    });
  }

  void initGeoFireListener() {
    Geofire.initialize("availableDrivers");
    //comment
    Geofire.queryAtLocation(
            currentPosition.latitude, currentPosition.longitude, 15)
        .listen((map) {
      print(map);
      if (map != null) {
        var callBack = map['callBack'];

        //latitude will be retrieved from map['latitude']
        //longitude will be retrieved from map['longitude']

        switch (callBack) {
          case Geofire.onKeyEntered:
            NearbyAvailableDrivers nearbyAvailableDrivers =
                NearbyAvailableDrivers();
            nearbyAvailableDrivers.key = map['key'];
            nearbyAvailableDrivers.latitude = map['latitude'];
            nearbyAvailableDrivers.longitude = map['longitude'];
            GeoFireAssistant.nearbyAvailableDriversList
                .add(nearbyAvailableDrivers);
            if (nearbyAvailableDriverKeysLoaded == true) {
              updateAvailableDriversOnMap();
            }
            break;

          case Geofire.onKeyExited:
            GeoFireAssistant.removeDriverFromList(map['key']);
            updateAvailableDriversOnMap();
            break;

          case Geofire.onKeyMoved:
            NearbyAvailableDrivers nearbyAvailableDrivers =
                NearbyAvailableDrivers();
            nearbyAvailableDrivers.key = map['key'];
            nearbyAvailableDrivers.latitude = map['latitude'];
            nearbyAvailableDrivers.longitude = map['longitude'];
            GeoFireAssistant.updateDriverNearbyLocation(nearbyAvailableDrivers);
            updateAvailableDriversOnMap();

            break;

          case Geofire.onGeoQueryReady:
            updateAvailableDriversOnMap();
            break;
        }
      }

      setState(() {});
    });
    //comment
  }

  void updateAvailableDriversOnMap() {
    setState(() {
      markersSet.clear();
    });
    Set<Marker> tMarkers = Set<Marker>();
    for (NearbyAvailableDrivers driver
        in GeoFireAssistant.nearbyAvailableDriversList) {
      LatLng driverAvailablePosition =
          LatLng(driver.latitude, driver.longitude);
      Marker marker = Marker(
        markerId: MarkerId('driver${driver.key}'),
        position: driverAvailablePosition,
        icon: nearbyIcon,
        rotation: AssistantMethods.createRandomNumber(360),
      );
      tMarkers.add(marker);
    }
    setState(() {
      markersSet = tMarkers;
    });
  }

  void createIconMarker() {
    if (nearbyIcon == null) {
      ImageConfiguration imageConfiguration =
          createLocalImageConfiguration(context, size: Size(2, 2));
      BitmapDescriptor.fromAssetImage(
              imageConfiguration, "images/car_android.png")
          .then((value) {
        nearbyIcon = value;
      });
    }
  }

  void noDriverFound() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => NoDriverAvailableDialog());
  }

  void searchNearestDriver() {
    if (availableDrivers!.length == 0) {
      cancelRideRequest();
      resetApp();
      noDriverFound();
      return;
    }
    var driver = availableDrivers![0];
    driversRef
        .child(driver.key)
        .child("car_details")
        .child("type")
        .once()
        .then((DataSnapshot snap) async {
      if (await snap.value != null) {
        String carType = snap.value.toString();
        if (carType == carRideType) {
          notifyDriver(driver);
          availableDrivers!.removeAt(0);
        } else {
          displayToastMessage(
              carRideType + "drivers not available.Try again", context);
        }
      } else {
        displayToastMessage(carRideType + "No car found.Try again", context);
      }
    });
  }

  void notifyDriver(NearbyAvailableDrivers driver) {
    driversRef.child(driver.key).child("newRide").set(rideRequestRef!.key);

    driversRef
        .child(driver.key)
        .child("token")
        .once()
        .then((DataSnapshot snap) {
      if (snap.value != null) {
        String token = snap.value.toString();
        AssistantMethods.sendNotificationToDriver(
            token, context, rideRequestRef!.key);
      } else {
        return;
      }
      const oneSecondPassed = Duration(seconds: 1);
      var timer = Timer.periodic(oneSecondPassed, (timer) {
        if (state != "requesting") {
          driversRef.child(driver.key).child("newRide").set("cancelled");
          driversRef.child(driver.key).child("newRide").onDisconnect();
          driverRequestTimeOut = 40;
          timer.cancel();
        }
        driverRequestTimeOut = driverRequestTimeOut - 1;

        driversRef.child(driver.key).child("newRide").onValue.listen((event) {
          if (event.snapshot.value.toString() == "accepted") {
            driversRef.child(driver.key).child("newRide").onDisconnect();
            driverRequestTimeOut = 40;
            timer.cancel();
          }
        });
        if (driverRequestTimeOut == 0) {
          driversRef.child(driver.key).child("newRide").set("timeout");
          driversRef.child(driver.key).child("newRide").onDisconnect();
          driverRequestTimeOut = 40;
          timer.cancel();
          searchNearestDriver();
        }
      });
    });
  }
}

// Column(
// crossAxisAlignment: CrossAxisAlignment.start,
// children: [
// Container(
// height: 55.0,
// width: 55.0,
// decoration: BoxDecoration(
// borderRadius:
// BorderRadius.all(Radius.circular(26.0)),
// border:
// Border.all(width: 2.0, color: Colors.black),
// ),
// child: Icon(
// Icons.call,
// color: Colors.black,
// ),
// ),
// SizedBox(
// height: 10.0,
// ),
// Text("Call"),
// ],
// ),
// Column(
// crossAxisAlignment: CrossAxisAlignment.start,
// children: [
// Container(
// height: 55.0,
// width: 55.0,
// decoration: BoxDecoration(
// borderRadius:
// BorderRadius.all(Radius.circular(26.0)),
// border:
// Border.all(width: 2.0, color: Colors.black),
// ),
// child: Icon(
// Icons.list,
// color: Colors.black,
// ),
// ),
// SizedBox(
// height: 10.0,
// ),
// Text("Details"),
// ],
// ),
// Column(
// crossAxisAlignment: CrossAxisAlignment.start,
// children: [
// Container(
// height: 55.0,
// width: 55.0,
// decoration: BoxDecoration(
// borderRadius:
// BorderRadius.all(Radius.circular(26.0)),
// border:
// Border.all(width: 2.0, color: Colors.black),
// ),
// child: Icon(
// Icons.close,
// color: Colors.black,
// ),
// ),
// SizedBox(
// height: 10.0,
// ),
// Text("Cancel"),
// ],
// ),
