#import "RPL10n.h"
static NSString *gOverride = nil;
static NSDictionary *RPL10nTable(void){
    #define FR(x) x
    static NSDictionary *t=nil; static dispatch_once_t once; dispatch_once(&once,^{ t=@{
        @"panel.title":@{@"fr":FR(@"Raptor"),@"en":@"Raptor"},
        @"panel.active":@{@"fr":FR(@"Actif"),@"en":@"Active"},
        @"panel.manage":@{@"fr":FR(@"Gérer"),@"en":@"Manage"},
        @"panel.create":@{@"fr":FR(@"Nouveau conteneur"),@"en":@"New container"},
        @"panel.activate":@{@"fr":FR(@"Activer ce conteneur"),@"en":@"Activate container"},
        @"panel.rename":@{@"fr":FR(@"Renommer"),@"en":@"Rename"},
        @"panel.delete":@{@"fr":FR(@"Supprimer"),@"en":@"Delete"},
        @"panel.camera":@{@"fr":FR(@"Caméra globale"),@"en":@"Global camera"},
        @"panel.reset":@{@"fr":FR(@"Tout réinitialiser"),@"en":@"Reset all"},
        @"panel.degraded":@{@"fr":FR(@"⚠️ isolation inactive — redémarrage requis"),@"en":@"⚠️ isolation degraded — restart required"},
        @"panel.activated.m":@{@"fr":FR(@"« %@ » est prêt.\nL'app va se fermer — rouvre-la pour l'utiliser."),@"en":@"“%@” is ready.\nThe app will close — reopen it to use it."},
        @"create.title":@{@"fr":FR(@"Nouveau conteneur"),@"en":@"New container"},
        @"create.edit":@{@"fr":FR(@"Modifier"),@"en":@"Edit"},
        @"create.name":@{@"fr":FR(@"Nom du conteneur"),@"en":@"Container name"},
        @"create.name.ph":@{@"fr":FR(@"ex : Perso"),@"en":@"e.g. Personal"},
        @"create.model":@{@"fr":FR(@"Modèle"),@"en":@"Model"},
        @"create.ios":@{@"fr":FR(@"iOS"),@"en":@"iOS"},
        @"create.language":@{@"fr":FR(@"Langue"),@"en":@"Language"},
        @"create.region":@{@"fr":FR(@"Région"),@"en":@"Region"},
        @"create.save":@{@"fr":FR(@"Enregistrer"),@"en":@"Save"},
        @"gps.title":@{@"fr":FR(@"Position"),@"en":@"Location"},
        @"gps.clear":@{@"fr":FR(@"Effacer"),@"en":@"Clear"},
        @"gps.search.ph":@{@"fr":FR(@"Rechercher une ville"),@"en":@"Search a city"},
        @"gps.hint":@{@"fr":FR(@"Appui long sur la carte pour choisir"),@"en":@"Long-press the map to pick"},
        @"common.cancel":@{@"fr":FR(@"Annuler"),@"en":@"Cancel"},
        @"common.ok":@{@"fr":FR(@"OK"),@"en":@"OK"},
        @"common.delete":@{@"fr":FR(@"Supprimer"),@"en":@"Delete"},
        @"common.auto":@{@"fr":FR(@"Automatique (système)"),@"en":@"Automatic (system)"},
        @"panel.auto":@{@"fr":FR(@"Automatique (système)"),@"en":@"Automatic (system)"},
    };});
    return t;
}
NSString *RPLang(void){
    if (gOverride.length) return gOverride;
    NSString *pref = [NSLocale preferredLanguages].firstObject ?: @"fr";
    NSString *base = [[pref componentsSeparatedByString:@"-"].firstObject lowercaseString] ?: @"fr";
    if ([@[@"fr",@"en",@"es",@"de",@"it",@"pt"] containsObject:base]) return base;
    return @"fr";
}
NSString *RPLL(NSString *k, NSString *fb){
    NSDictionary *e = RPL10nTable()[k];
    NSString *lang = RPLang();
    NSString *v = e[lang] ?: e[@"fr"] ?: fb;
    return v ?: fb;
}
@implementation RPL10n
+ (void)setOverrideLanguage:(NSString *)l { gOverride=[l copy]; [[NSUserDefaults standardUserDefaults] setObject:l forKey:@"RPLangOverride"]; }
+ (NSString *)overrideLanguage { if(gOverride) return gOverride; return [[NSUserDefaults standardUserDefaults] stringForKey:@"RPLangOverride"]; }
@end
