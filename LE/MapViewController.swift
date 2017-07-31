//
//  MapViewController.swift
//  LE
//
//  Created by Rahil Patel on 11/12/16.
//  Copyright © 2016 Rahil. All rights reserved.
//

// things to add:
// event title then separate description bar (click to see more details button)
// change time of event disappearance to 30 minutes after event
// or you can make an end time 
// allow creator to edit event (will need to add an array of events created by a user under a specific profile

import UIKit
import Firebase
import GooglePlacePicker
import GoogleMaps
import CoreLocation
import FirebaseDatabase
import FirebaseStorage


extension NSDate
{
    func hour() -> Int
    {
        //Get Hour
        let calendar = NSCalendar.current
        
        let hour = calendar.component(.hour, from: self as Date)
        
        //Return Hour
        return hour
    }
    
    
    func minute() -> Int
    {
        //Get Minute
        let calendar = NSCalendar.current

        let minute = calendar.component(.minute, from: self as Date)
        
        //Return Minute
        return minute
    }
    
    func toShortTimeString() -> String
    {
       
        //Get Short Time String
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeString = formatter.string(from: self as Date)
        
        //Return Short Time String
        return timeString
    }
}


class MapViewController: UIViewController, CLLocationManagerDelegate, GMSMapViewDelegate {
    //for debugging
    
    let childRef = FIRDatabase.database().reference(withPath: "Events")
    let userRef = FIRDatabase.database().reference(withPath: "Users")
    let storageRef = FIRStorage.storage().reference()
    
    var events: [Event] = []
    var markers: [GMSMarker] = []
    var pickedEventID:String = ""
    var cameraHasBeenSetToCurrentPositionAtLeastOnce:Bool = false
    var cameraPosition:GMSCameraPosition? = nil

    var currentUser:User!
    var mapView: GMSMapView = GMSMapView.map(withFrame: CGRect.zero, camera: GMSCameraPosition.camera(withLatitude: 0,longitude:0, zoom:6))
    
    let locationManager = CLLocationManager()
    
    //Google Map Locations variables
    var selectedRoute: Dictionary<String, AnyObject>!
    var overviewPolyline: Dictionary<String, AnyObject>!
    var originCoordinate: CLLocationCoordinate2D!
    var destinationCoordinate: CLLocationCoordinate2D!
    var originAddress: String!
    var destinationAddress: String!
    var routePolyline: GMSPolyline!
    
    //just the image of the button
    @IBOutlet weak var PressButton: UIButton!
    @IBOutlet var OpenSideBar: UIButton!
    @IBAction func PushButton(_ sender: Any, forEvent event: UIEvent) {
    }
    
    // MARK: - View methods
    override func viewDidLoad() {
        
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        currentUser = User(data: UserData())
        mapView.delegate = self
        view.addSubview(mapView)
        
        
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        
        if CLLocationManager.locationServicesEnabled() {
            // 4
            locationManager.startUpdatingLocation()
            //5

            mapView.isMyLocationEnabled = true
            mapView.settings.myLocationButton = true
            view = mapView
            
        }

        self.navigationController?.isNavigationBarHidden = true
        
        layoutButtons()
        view.addSubview(self.PressButton)
        view.addSubview(self.OpenSideBar)
        
        OpenSideBar.addTarget(self.revealViewController(), action: #selector(SWRevealViewController.revealToggle(_:)), for: .touchUpInside)
        //self.revealViewController().rearViewRevealWidth = self.view.frame.width - 200

    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        if CLLocationManager.locationServicesEnabled() {
            // 4
            locationManager.startUpdatingLocation()
            //5
            
            mapView.isMyLocationEnabled = true
            mapView.settings.myLocationButton = true
            view = mapView
            
            if let cameraPos = cameraPosition {
                mapView.camera = cameraPos
            }
            
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateMap()
        self.navigationController?.isNavigationBarHidden = true
        print("Button Position:::  (\(PressButton.frame.midX),\(PressButton.frame.midY)")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        cameraPosition = mapView.camera
    }
    
    // MARK: - GMSMapView Delegate methods
    func mapView(_ mapView: GMSMapView, didTapInfoWindowOf marker: GMSMarker) {
        //perform segue depending on the event
        
        pickedEventID = marker.userData as! String
        performSegue(withIdentifier: "EventDetails", sender: marker)
    }
    func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
        //remove any previous polylines
        mapView.clear()
        for marker in markers {
            marker.appearAnimation = kGMSMarkerAnimationNone
            marker.map = self.mapView
            
        }
        
        //draw polyline from current location to marker
        if let coord = locationManager.location?.coordinate {
            
            var coordBounds:GMSCoordinateBounds = GMSCoordinateBounds(coordinate: coord, coordinate: marker.position)
            
            let insets:UIEdgeInsets = UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50)
            mapView.animate(to: mapView.camera(for: coordBounds, insets: insets)!)
            drawPath(startLocation: coord, endLocation: marker.position) { (status, success) in
                if success {
                    self.drawRoute()
                    coordBounds = coordBounds.includingPath(self.routePolyline.path!)
                    mapView.animate(to: mapView.camera(for: coordBounds, insets: insets)!)
                }
            }
            
            return true
        }
        else {
            return false
        }
    }
    
    // MARK: - CLLocationManager delegate methods
    private func locationManager1(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse {
            
            locationManager.startUpdatingLocation()
            
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        if !cameraHasBeenSetToCurrentPositionAtLeastOnce {
            if let location = locations.first {
                mapView.camera = GMSCameraPosition(target: location.coordinate, zoom: 15, bearing: 0, viewingAngle: 0)
                
                locationManager.stopUpdatingLocation()
            }
            cameraHasBeenSetToCurrentPositionAtLeastOnce = true
        }
    }
    
    // MARK: - Segue methods
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        locationManager.stopUpdatingLocation()
        if segue.identifier == "EventDetails" {
            let nextController = (segue.destination as! EventDetailsVC)
            childRef.observeSingleEvent(of: .value, with: { snapshot in
                for item in snapshot.children {
                    let snap = item as! FIRDataSnapshot
                    if snap.key == self.pickedEventID {
                        let event:Event = Event(snapshot: snap)
                        
                        print(event)
                        
                        EventVariables.address = event.address
                        EventVariables.dateDay = Int(event.day)!
                        EventVariables.dateMonth = Int(event.month)!
                        EventVariables.dateYear = Int(event.year)!
                        EventVariables.description = event.description
                        EventVariables.latitude = event.latitude
                        EventVariables.longitude = event.longitude
                        EventVariables.timeHr = Int(event.hour)!
                        EventVariables.timeMin = Int(event.minute)!
                        EventVariables.eventID = self.pickedEventID
                        EventVariables.createdByUID = event.createdByUID
                        EventVariables.invitedFriends = event.invitedFriends
                        EventVariables.isPublic = event.isPublic
                        
                        self.userRef.child("User: \(event.createdByUID)").observeSingleEvent(of: .value,with: { snapshot in
                            nextController.eventCreator = User(snapshot: snapshot)
                            nextController.setTitle() //This is what causes a switch to be added
                        })
                    }
                }
            })
            
        }
    }
    
    // MARK: - Private convenience methods
    
    //MARK: laying out mapView
    func updateMap() {
        mapView.clear()
        childRef.observeSingleEvent(of: .value, with: { snapshot in
            // 2
            var newEvents: [Event] = []
            // 3
            for item in snapshot.children {
                // 4
                let snap = item as! FIRDataSnapshot
                let event = Event(snapshot: snap)
                
                //let thirtyPast: Bool = self.isThirtyPastCurrentTime(date: NSDate(), hour: Int(event.hour)!, minute: Int(event.minute)!, day: Int(event.day)!, month: Int(event.month)!, year: Int(event.year)!)
                let allowedToView: Bool = self.isAllowedToViewEvent(isPublic:event.isPublic, friendsAllowed: event.invitedFriends, tag:snap.key)
                if allowedToView {
                    newEvents.append(event)
                    self.createMarker(hour:event.hour, minute:event.minute, address:event.address, latitude:event.latitude, longitude:event.longitude, description:event.description, day:event.day, month:event.month, year:event.year, tag:snap.key, uid:event.createdByUID)
                    
                    
                    
                }
            }
            // 5
            self.events = newEvents
        })
        
    }
    
    func createMarker(hour:String, minute:String, address:String, latitude:Double, longitude:Double, description:String, day:String, month:String, year:String, tag:String, uid:String) {
        var newHr:Int = Int(hour)!
        var newMin = minute
        var AMPMstr = " AM"
        if newHr == 0 {
            newHr = 12
        }
        else if newHr > 12 {
            newHr -= 12
            AMPMstr = " PM"
        }
        if Int(newMin)! < 10 {
            newMin = "0" + newMin
        }
        let timeStr = String(newHr) + ":" + newMin + AMPMstr
        
        let marker = GMSMarker()
        
        if userCreatedEvent(withTag: tag) {
            marker.icon = GMSMarker.markerImage(with: UIColor.blue)
        }
        else {
            marker.icon = GMSMarker.markerImage(with: nil)
        }
 
        marker.position = GMSCameraPosition.camera(withLatitude: CLLocationDegrees(latitude),longitude:CLLocationDegrees(longitude), zoom:6).target
        marker.snippet = description + "\n" + month + "/" + day + "/" + year + "\n" + timeStr + "\n" + address
        marker.userData = tag
        marker.appearAnimation = kGMSMarkerAnimationPop
        marker.map = mapView
        //until the profile picture is loaded
        marker.iconView = setupMarkerView(profilePic: #imageLiteral(resourceName: "DefaultProfileImg"))
        marker.tracksViewChanges = true
        marker.infoWindowAnchor = CGPoint(x: 0.5, y: 0.25)
        markers.append(marker)
        updateMarkerView(uid: uid, marker: marker)
        
    }

    func drawPath(startLocation:CLLocationCoordinate2D, endLocation:CLLocationCoordinate2D, completionHandler: @escaping ((_ status: String, _ success: Bool) -> Void)) {
        let origin = "\(startLocation.latitude),\(startLocation.longitude)"
        let destination = "\(endLocation.latitude),\(endLocation.longitude)"
        let url = "https://maps.googleapis.com/maps/api/directions/json?origin=\(origin)&destination=\(destination)&mode=driving"
        //url = url.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
        let directionsURL = URL(string: url)
        print(url)
        DispatchQueue.main.async {
            do {
                let directionsData = try Data(contentsOf: directionsURL!)
                print("VALID DATA")
                do {
                    let dict = try JSONSerialization.jsonObject(with: directionsData, options: JSONSerialization.ReadingOptions.mutableContainers)
                    if let dictionary = dict as? [String:AnyObject] {
                        
                        
                            let status = dictionary["status"] as! String
                
                            if status == "OK" {
                                self.selectedRoute = (dictionary["routes"] as! Array<Dictionary<String, AnyObject>>)[0]
                                self.overviewPolyline = self.selectedRoute["overview_polyline"] as! Dictionary<String, AnyObject>
                    
                                let legs = self.selectedRoute["legs"] as! Array<Dictionary<String, AnyObject>>
                    
                                let startLocationDictionary = legs[0]["start_location"] as! Dictionary<String, AnyObject>
                                self.originCoordinate = CLLocationCoordinate2DMake(startLocationDictionary["lat"] as! Double, startLocationDictionary["lng"] as! Double)
                    
                                let endLocationDictionary = legs[legs.count - 1]["end_location"] as! Dictionary<String, AnyObject>
                                self.destinationCoordinate = CLLocationCoordinate2DMake(endLocationDictionary["lat"] as! Double, endLocationDictionary["lng"] as! Double)
                    
                                self.originAddress = legs[0]["start_address"] as! String
                                self.destinationAddress = legs[legs.count - 1]["end_address"] as! String
                                completionHandler(status, true)
                    //self.calculateTotalDistanceAndDuration()
                    
                            }
                            else {
                    completionHandler(status, false)
                            }
                
                        }
                }
                
                catch {
                    print("json error: \(error.localizedDescription)")
                    completionHandler("",false)

                }
            }
            catch {
                print("invalid data error: \n\(error)")
            }
        }
        
    }
    
    func drawRoute() {
        let route = self.overviewPolyline["points"] as! String
        
        let path: GMSPath = GMSPath(fromEncodedPath: route)!
        routePolyline = GMSPolyline(path: path)
        routePolyline.strokeWidth = 4
        routePolyline.strokeColor = Colors.blueGreen
        routePolyline.map = mapView
    }
    
    private func isAllowedToViewEvent(isPublic:Bool, friendsAllowed:[String], tag:String) -> Bool {
        var isAllowed = false
        var userCreatedThisEvent = false
        for friend in friendsAllowed {
            if friend == currentUser.getUserID() {
                isAllowed = true
            }
        }
        
        userCreatedThisEvent = userCreatedEvent(withTag: tag)
        //print("Public: \(isPublic)   Allowed: \(isAllowed)   User Created This: \(userCreatedThisEvent)")
        return isPublic || isAllowed || userCreatedThisEvent
    }
    private func userCreatedEvent(withTag tag:String) -> Bool {
        var userCreatedThisEvent = false
        for event in currentUser.createdEvents {
            if event == tag {
                userCreatedThisEvent = true
            }
        }
        return userCreatedThisEvent
    }
    private func isThirtyPastCurrentTime(date: NSDate, hour: Int, minute: Int, day: Int, month:Int, year:Int) -> Bool {
        var tempMin = minute
        var tempHr = hour
        var tempDay = day
        var tempMonth = month
        var tempYear = year
        
        let thisYear = Calendar.current.component(.year, from: date as Date)
        let thisMonth =  Calendar.current.component(.month, from: date as Date)
        let thisDay =  Calendar.current.component(.day, from: date as Date)
        
        //can replace 30 with a variable for how long after the start time you want the event to be visible
        while ((tempMin + 30) >= 60) {
            tempMin = minute + 30 - 60
            tempHr += 1
        }
        if (tempHr > 24) {
            tempHr = 1
            tempDay += 1
        }
        if (month == 1||month == 3||month == 5||month == 7||month == 8||month == 10||month == 12) {
            if (day == 31) {
                tempMonth += 1
            }
        }
        else if (month == 2){ // @saif
            if (year-2000 % 4 == 0) {
                if (day == 29) {
                    tempMonth += 1
                }
            }
            else {
                if (day == 28) {
                    tempMonth += 1
                }
            }
        }
        else {
            if (day == 30) {
                tempMonth += 1
            }
        }
        if (tempMonth > 12) {
            tempYear += 1
        }
        
        
        let expireTime = "\(tempHr):\(tempMin)"
        let expireDate = "\(tempMonth)/\(tempDay)/\(tempYear)"
        //print("Expire Time and Date: \(expireTime)\n\(expireDate)")
        
        if (tempYear > thisYear) {
            return false
        }
        else if (tempYear == thisYear && tempMonth > thisMonth) {
            return false
        }
        else if (tempYear == thisYear && tempMonth == thisMonth && tempDay > thisDay){
            return false
        }
        else if (tempYear == thisYear && tempMonth == thisMonth && tempDay == thisDay && tempHr > date.hour()) {
            return false
        }
        else if (tempYear == thisYear && tempMonth == thisMonth && tempDay == thisDay && tempHr == date.hour() && tempMin > date.minute()) {
            return false
        }
        else {
            return true
        }
    }
    
    // MARK: UI Stuff
    private func layoutButtons() {
        let width = UIScreen.main.bounds.width
        let height = UIScreen.main.bounds.height
        let btnWidth = height/15 //so width and height are equal
        let btnHeight = height/15
        let offset:CGFloat = 30
        let size = CGSize(width: btnWidth, height: btnHeight)
        let origin = CGPoint(x: width - btnWidth - offset/4 , y: offset)
        //PressButton.frame = CGRect(origin: CGPoint(x: 8 * width / 9, y: height / 50), size: CGSize(width: height / 11, height: height / 11))
        PressButton.frame = CGRect(origin: origin, size: size)
        OpenSideBar.frame = CGRect(origin: CGPoint(x: 7 * width / 320, y: height / 25), size: CGSize(width: height / 22, height: height / 22))
        
    }
    
    private func setupMarkerView(profilePic: UIImage) -> UIImageView {
        let markerOutline = UIImage(named: "CustomMarker.png")!
        let markerView = UIImageView()

        let size = CGSize(width: 60, height: 96)
        UIGraphicsBeginImageContext(size)
        let areaSize = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        markerOutline.draw(in: areaSize)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        markerView.frame = areaSize
        markerView.image = newImage
        
        let imgView = UIImageView()
        markerView.addSubview(imgView)
        let xPos: CGFloat = imgView.superview!.frame.width / 4.0
        let yPos: CGFloat = imgView.superview!.frame.height / 3.878787878787
        let width: CGFloat = imgView.superview!.frame.width / 2
        let height: CGFloat = width
        let frame = CGRect(x: xPos, y: yPos, width: width, height: height)
        imgView.frame = frame
        imgView.image = profilePic
        imgView.layer.masksToBounds = true
        imgView.clipsToBounds = true
        imgView.layer.cornerRadius = imgView.layer.bounds.width/2.0
        
        return markerView
    }
    
    private func updateMarkerView(uid:String, marker:GMSMarker) {
        
        let filePath = "Users/User: \(uid)/\("profilePicture")"
        self.storageRef.child(filePath).data(withMaxSize: 10*1024*1024, completion: { (data, error) in
            if error == nil {
                let userPhoto = UIImage(data: data!)
                
                marker.iconView = self.setupMarkerView(profilePic: userPhoto!)
            }
            else {
                //error
            }
            marker.tracksViewChanges = false
        })
    }
    
}
