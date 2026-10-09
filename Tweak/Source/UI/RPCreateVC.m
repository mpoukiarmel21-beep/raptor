#import "RPCreateVC.h"
#import "RPContainer.h"
#import "RPContainerStore.h"
#import "RPDeviceIdentity.h"
#import "RPLocaleSpoof.h"
#import "RPTheme.h"
#import "RPL10n.h"
#import "RPListPickerVC.h"

@interface RPCreateVC () <UITextFieldDelegate>
@property (nonatomic, strong, nullable) RPContainer *editing;
@property (nonatomic, copy) NSString *seedCID;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, copy) NSString *chosenModel, *chosenIOS, *chosenMarketing;
@property (nonatomic, copy) NSString *appLanguage, *regionCountry;
@end

@implementation RPCreateVC

- (instancetype)initWithContainer:(RPContainer *)c {
    self=[super initWithStyle:UITableViewStyleInsetGrouped];
    if(self){
        _editing=c;
        if(c){
            _chosenModel=c.deviceModel.length?c.deviceModel:[RPDeviceIdentity seededModelForCID:c.cid].identifier;
            _chosenIOS=c.iosVersion.length?c.iosVersion:[RPDeviceIdentity seededIOSVersionForCID:c.cid];
            _chosenMarketing=c.marketingName ?: [RPDeviceIdentity marketingNameForIdentifier:_chosenModel];
            _appLanguage=c.appLanguage ?: @"";
            _regionCountry=c.regionCountry ?: @"";
            _seedCID=c.cid;
        } else {
            _seedCID=[[NSUUID UUID] UUIDString];
            _chosenModel=[RPDeviceIdentity seededModelForCID:_seedCID].identifier;
            _chosenMarketing=[RPDeviceIdentity marketingNameForIdentifier:_chosenModel];
            _chosenIOS=[RPDeviceIdentity seededIOSVersionForCID:_seedCID];
            _appLanguage=[RPLocaleSpoof deviceLanguage] ?: @"";
            _regionCountry=[RPLocaleSpoof deviceRegion] ?: @"";
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.title=_editing ? RPLL(@"create.edit",@"Modifier") : RPLL(@"create.title",@"Nouveau conteneur");
    self.view.backgroundColor=[RPTheme panelBackground]; self.tableView.backgroundColor=[RPTheme panelBackground];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:RPLL(@"create.save",@"Enregistrer") style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItem.tintColor=[RPTheme accent];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tv { return 1; }
- (NSInteger)tableView:(UITableView*)tv numberOfRowsInSection:(NSInteger)s { return 5; }

- (UITableViewCell*)tableView:(UITableView*)tv cellForRowAtIndexPath:(NSIndexPath*)ip {
    UITableViewCell *cell=[tv dequeueReusableCellWithIdentifier:@"c"];
    if(!cell){
        cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
        cell.backgroundView=[[UIView alloc] init];
        cell.backgroundView.backgroundColor=[RPTheme glassFill];
        cell.backgroundView.layer.cornerRadius=14; cell.backgroundView.clipsToBounds=YES;
        cell.backgroundView.layer.borderColor=[RPTheme glassStroke].CGColor; cell.backgroundView.layer.borderWidth=1;
        cell.selectedBackgroundView=[[UIView alloc] init];
        cell.selectedBackgroundView.backgroundColor=[UIColor colorWithWhite:1 alpha:0.06];
    }
    // always reset
    cell.textLabel.textColor=[RPTheme primaryText];
    cell.detailTextLabel.textColor=[RPTheme secondaryText];
    cell.tintColor=[RPTheme accent];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    cell.accessoryView=nil;
    cell.backgroundColor=[UIColor clearColor];
    switch(ip.row){
        case 0: {
            cell.textLabel.text=RPLL(@"create.name",@"Nom du conteneur");
            cell.accessoryType=UITableViewCellAccessoryNone;
            cell.detailTextLabel.text=nil;
            if(!_nameField){
                _nameField=[[UITextField alloc] initWithFrame:CGRectMake(0,0,170,30)];
                _nameField.placeholder=RPLL(@"create.name.ph",@"ex : Perso");
                _nameField.text=_editing.name;
                _nameField.textColor=[RPTheme primaryText];
                _nameField.attributedPlaceholder=[[NSAttributedString alloc] initWithString:_nameField.placeholder attributes:@{NSForegroundColorAttributeName:[RPTheme secondaryText]}];
                _nameField.textAlignment=NSTextAlignmentRight;
                _nameField.delegate=self; _nameField.returnKeyType=UIReturnKeyDone;
                _nameField.font=[UIFont systemFontOfSize:15];
            }
            cell.accessoryView=_nameField;
            break;
        }
        case 1: cell.textLabel.text=RPLL(@"create.model",@"Modèle"); cell.detailTextLabel.text=[RPDeviceIdentity marketingNameForIdentifier:_chosenModel]; break;
        case 2: cell.textLabel.text=RPLL(@"create.ios",@"iOS"); cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ (%@)", _chosenIOS, [RPDeviceIdentity buildForIOSVersion:_chosenIOS]]; break;
        case 3: cell.textLabel.text=RPLL(@"create.language",@"Langue"); cell.detailTextLabel.text=_appLanguage.length?[RPLocaleSpoof displayNameForLanguage:_appLanguage]:RPLL(@"panel.auto",@"Automatique (système)"); break;
        case 4: cell.textLabel.text=RPLL(@"create.region",@"Région"); cell.detailTextLabel.text=_regionCountry.length?[RPLocaleSpoof displayNameForRegion:_regionCountry]:RPLL(@"panel.auto",@"Automatique (système)"); break;
    }
    return cell;
}

- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if(ip.row==0){ [_nameField becomeFirstResponder]; return; }
    __weak typeof(self) weakSelf=self;
    if(ip.row==1){
        NSArray *models=[RPDeviceIdentity modelsForRealChip];
        NSMutableArray *opts=[NSMutableArray array];
        for(NSValue *v in models){ RPDeviceModel m=[RPDeviceIdentity unboxModel:v]; [opts addObject:[RPListOption optionWithValue:m.identifier title:m.marketingName subtitle:[NSString stringWithFormat:@"%@ · %@", m.identifier, m.chipFamily]]]; }
        RPListPickerVC *p=[[RPListPickerVC alloc] initWithTitle:@"Modèle" options:opts selectedValue:_chosenModel onPick:^(RPListOption *o){
            __strong typeof(weakSelf) s=weakSelf; if(!s) return;
            s.chosenModel=o.value; s.chosenMarketing=[RPDeviceIdentity marketingNameForIdentifier:o.value]; [s.tableView reloadData];
        }];
        [self.navigationController pushViewController:p animated:YES];
    } else if(ip.row==2){
        NSArray *vs=[RPDeviceIdentity iosVersions];
        NSMutableArray *opts=[NSMutableArray array];
        for(NSString *v in vs) [opts addObject:[RPListOption optionWithValue:v title:v subtitle:[RPDeviceIdentity buildForIOSVersion:v]]];
        RPListPickerVC *p=[[RPListPickerVC alloc] initWithTitle:@"iOS" options:opts selectedValue:_chosenIOS onPick:^(RPListOption *o){
            __strong typeof(weakSelf) s=weakSelf; if(!s) return;
            s.chosenIOS=o.value; [s.tableView reloadData];
        }];
        [self.navigationController pushViewController:p animated:YES];
    } else if(ip.row==3){
        NSMutableArray *opts=[NSMutableArray array];
        [opts addObject:[RPListOption optionWithValue:@"" title:RPLL(@"panel.auto",@"Automatique") subtitle:nil]];
        for(NSString *c in [RPLocaleSpoof supportedLanguageCodes]) [opts addObject:[RPListOption optionWithValue:c title:[RPLocaleSpoof displayNameForLanguage:c] subtitle:c]];
        RPListPickerVC *p=[[RPListPickerVC alloc] initWithTitle:@"Langue" options:opts selectedValue:_appLanguage onPick:^(RPListOption *o){
            __strong typeof(weakSelf) s=weakSelf; if(!s) return;
            s.appLanguage=o.value; [s.tableView reloadData];
        }];
        [self.navigationController pushViewController:p animated:YES];
    } else if(ip.row==4){
        NSMutableArray *opts=[NSMutableArray array];
        [opts addObject:[RPListOption optionWithValue:@"" title:RPLL(@"panel.auto",@"Automatique") subtitle:nil]];
        for(NSString *c in [RPLocaleSpoof supportedRegionCodes]) [opts addObject:[RPListOption optionWithValue:c title:[RPLocaleSpoof displayNameForRegion:c] subtitle:c]];
        RPListPickerVC *p=[[RPListPickerVC alloc] initWithTitle:@"Région" options:opts selectedValue:_regionCountry onPick:^(RPListOption *o){
            __strong typeof(weakSelf) s=weakSelf; if(!s) return;
            s.regionCountry=o.value; [s.tableView reloadData];
        }];
        [self.navigationController pushViewController:p animated:YES];
    }
}

- (NSString*)tableView:(UITableView*)tv titleForFooterInSection:(NSInteger)s { return @"Modèles limités à la puce réelle (même génération)"; }
- (void)tableView:(UITableView*)tv willDisplayFooterView:(UIView*)v forSection:(NSInteger)s {
    if([v isKindOfClass:[UITableViewHeaderFooterView class]]){
        ((UITableViewHeaderFooterView*)v).textLabel.textColor=[RPTheme secondaryText];
    }
}

- (void)save {
    NSString *name=[_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!name.length) name=@"Untitled";
    NSError *err=nil;
    if(_editing){
        [[RPContainerStore shared] renameContainer:_editing to:name error:nil];
        [[RPContainerStore shared] setDeviceModel:_chosenModel iosVersion:_chosenIOS marketingName:_chosenMarketing forContainer:_editing error:nil];
        [[RPContainerStore shared] setAppLanguage:(_appLanguage.length?_appLanguage:nil) region:(_regionCountry.length?_regionCountry:nil) forContainer:_editing error:nil];
    } else {
        RPContainer *c=[[RPContainerStore shared] createWithName:name cid:_seedCID error:&err];
        if(!c){ UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Erreur" message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; return; }
        [[RPContainerStore shared] setDeviceModel:_chosenModel iosVersion:_chosenIOS marketingName:_chosenMarketing forContainer:c error:nil];
        [[RPContainerStore shared] setAppLanguage:(_appLanguage.length?_appLanguage:nil) region:(_regionCountry.length?_regionCountry:nil) forContainer:c error:nil];
    }
    [self.navigationController popViewControllerAnimated:YES];
}
- (BOOL)textFieldShouldReturn:(UITextField*)tf { [tf resignFirstResponder]; return YES; }
@end
