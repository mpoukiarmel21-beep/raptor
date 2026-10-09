#import "RPMapPickerVC.h"
#import "RPContainer.h"
#import "RPContainerStore.h"
#import "RPTheme.h"
#import "RPL10n.h"
#import <MapKit/MapKit.h>
@interface RPMapPickerVC () <MKMapViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) RPContainer *container;
@property (nonatomic, copy) void(^onCommit)(void);
@property (nonatomic, strong) MKMapView *map;
@property (nonatomic, strong) UISearchBar *search;
@property (nonatomic, strong) UIButton *commitBtn;
@property (nonatomic, strong) MKPointAnnotation *pin;
@property (nonatomic, strong) CLGeocoder *geocoder;
@property (nonatomic, assign) CLLocationCoordinate2D chosen;
@property (nonatomic, copy) NSString *chosenName;
@property (nonatomic, assign) BOOL hasChosen;
@end
@implementation RPMapPickerVC
- (instancetype)initWithContainer:(RPContainer *)c onCommit:(void(^)(void))cb { self=[super init]; if(self){ _container=c; _onCommit=cb; _geocoder=[CLGeocoder new]; } return self; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[RPTheme panelBackground]; self.title=RPLL(@"gps.title",@"Position");
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:RPLL(@"gps.clear",@"Effacer") style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
    _search=[[UISearchBar alloc] init]; _search.placeholder=RPLL(@"gps.search.ph",@"Rechercher une ville"); _search.delegate=self; _search.searchBarStyle=UISearchBarStyleMinimal;
    _map=[[MKMapView alloc] init]; _map.delegate=self;
    _commitBtn=[UIButton buttonWithType:UIButtonTypeSystem];
    [_commitBtn setTitle:RPLL(@"gps.title",@"Position") forState:UIControlStateNormal];
    _commitBtn.backgroundColor=[RPTheme accent]; [_commitBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _commitBtn.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    _commitBtn.layer.cornerRadius=14; _commitBtn.clipsToBounds=YES;
    [_commitBtn addTarget:self action:@selector(commit) forControlEvents:UIControlEventTouchUpInside];
    _search.translatesAutoresizingMaskIntoConstraints=NO; _map.translatesAutoresizingMaskIntoConstraints=NO; _commitBtn.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:_search]; [self.view addSubview:_map]; [self.view addSubview:_commitBtn];
    [NSLayoutConstraint activateConstraints:@[
        [_search.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_search.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_search.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_map.topAnchor constraintEqualToAnchor:_search.bottomAnchor],
        [_map.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_map.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_map.bottomAnchor constraintEqualToAnchor:_commitBtn.topAnchor constant:-12],
        [_commitBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_commitBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_commitBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [_commitBtn.heightAnchor constraintEqualToConstant:52],
    ]];
    // gestures
    UILongPressGestureRecognizer *lp=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    lp.minimumPressDuration=0.4; lp.delegate=(id)self; [_map addGestureRecognizer:lp];
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKB)];
    tap.cancelsTouchesInView=NO; [self.view addGestureRecognizer:tap];
    [self loadInitial];
}
- (void)loadInitial {
    if (_container.hasLocation) {
        CLLocationCoordinate2D c=CLLocationCoordinate2DMake(_container.latitude.doubleValue, _container.longitude.doubleValue);
        _chosen=c; _hasChosen=YES; _chosenName=_container.locationName;
        [_map setRegion:MKCoordinateRegionMakeWithDistance(c, 20000, 20000) animated:NO];
        [self setPin:c name:_chosenName];
    } else {
        CLLocationCoordinate2D paris=CLLocationCoordinate2DMake(48.8566,2.3522);
        [_map setRegion:MKCoordinateRegionMakeWithDistance(paris, 200000, 200000) animated:NO];
    }
}
- (void)setPin:(CLLocationCoordinate2D)c name:(NSString*)n {
    if (_pin) [_map removeAnnotation:_pin];
    _pin=[[MKPointAnnotation alloc] init]; _pin.coordinate=c; _pin.title=n ?: @"📍";
    [_map addAnnotation:_pin];
}
- (void)longPress:(UILongPressGestureRecognizer*)gr {
    if (gr.state!=UIGestureRecognizerStateBegan) return;
    CGPoint p=[gr locationInView:_map];
    CLLocationCoordinate2D c=[_map convertPoint:p toCoordinateFromView:_map];
    _chosen=c; _hasChosen=YES;
    [self setPin:c name:nil];
    [self reverseGeocode:c];
}
- (void)reverseGeocode:(CLLocationCoordinate2D)c {
    CLLocation *loc=[[CLLocation alloc] initWithLatitude:c.latitude longitude:c.longitude];
    [_geocoder reverseGeocodeLocation:loc completionHandler:^(NSArray<CLPlacemark*>*ps, NSError*e){
        dispatch_async(dispatch_get_main_queue(), ^{
            CLPlacemark *p=ps.firstObject;
            NSString *city=p.locality ?: p.name ?: @"";
            NSString *country=p.country ?: p.ISOcountryCode ?: @"";
            self->_chosenName = city.length && country.length ? [NSString stringWithFormat:@"%@, %@", city, country] : (city.length?city:country);
            if (self->_pin) self->_pin.title=self->_chosenName;
        });
    }];
}
- (void)dismissKB { [_search resignFirstResponder]; }
- (void)searchBarSearchButtonClicked:(UISearchBar*)sb {
    NSString *q=sb.text; if(!q.length) return; [sb resignFirstResponder];
    MKLocalSearchRequest *req=[MKLocalSearchRequest new]; req.naturalLanguageQuery=q;
    [[[MKLocalSearch alloc] initWithRequest:req] startWithCompletionHandler:^(MKLocalSearchResponse *r,NSError*e){
        MKMapItem *item=r.mapItems.firstObject; if(!item) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_chosen=item.placemark.coordinate; self->_hasChosen=YES; self->_chosenName=item.name ?: item.placemark.locality;
            [self->_map setRegion:MKCoordinateRegionMakeWithDistance(self->_chosen, 30000, 30000) animated:YES];
            [self setPin:self->_chosen name:self->_chosenName];
        });
    }];
}
- (void)commit {
    if (!_hasChosen) { [self.navigationController popViewControllerAnimated:YES]; return; }
    NSError *err=nil;
    [[RPContainerStore shared] setLocation:@(_chosen.latitude) lng:@(_chosen.longitude) name:_chosenName forContainer:_container error:&err];
    if (_onCommit) _onCommit();
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)clear {
    NSError *err=nil;
    [[RPContainerStore shared] setLocation:nil lng:nil name:nil forContainer:_container error:&err];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:[NSString stringWithFormat:@"RP_loc_%@", _container.cid]];
    if (_onCommit) _onCommit();
    [self.navigationController popViewControllerAnimated:YES];
}
- (MKAnnotationView*)mapView:(MKMapView*)mv viewForAnnotation:(id<MKAnnotation>)ann {
    if ([ann isKindOfClass:[MKUserLocation class]]) return nil;
    MKMarkerAnnotationView *v=(MKMarkerAnnotationView*)[mv dequeueReusableAnnotationViewWithIdentifier:@"rp"]; if(!v) v=[[MKMarkerAnnotationView alloc] initWithAnnotation:ann reuseIdentifier:@"rp"];
    v.markerTintColor=[RPTheme accent]; v.animatesWhenAdded=YES; v.draggable=NO;
    return v;
}
@end
