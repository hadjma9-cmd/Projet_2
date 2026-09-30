pragma Singleton
import QtQuick

QtObject {
    property var themes: {
        return {
            // Theme de Gamaphone (anciennement « orange », nom herite de Linphone).
            // main500 = #187FA3 : la couleur de marque #2BA2B6, assombrie jusqu'au point ou un
            // texte blanc et un texte noir y sont aussi lisibles l'un que l'autre (4,56 et
            // 4,61:1). #2BA2B6 tel quel ne donnait que 3,02:1 au texte blanc des boutons.
            // Derivation : 100/200/300 = 80/60/40 % de blanc ; 600/700 = x0,80 / x0,68.
            "bleu_gama": {
                "main100": "#D1E5ED",
                "main200": "#A3CCDA",
                "main300": "#74B2C8",
                "main500": "#187FA3",
                "main600": "#136682",
                "main700": "#10566F",
                // Degrade de la barre laterale : moitie foncee du logo (#045091 -> #127FA9),
                // pour que les onglets et leur texte blanc restent lisibles (8,2 puis 4,6:1).
                "gradientTop": "#045091",
                "gradientBottom": "#187FA3",
                // Boutons : milieu du degrade, pour s'accorder a la barre laterale
                // (texte blanc a 6,1:1).
                "button": "#0E689A"
            },
            "yellow": {
                "main100": "#FFF5D6",
                "main200": "#FFEFB2",
                "main300": "#FFE799",
                "main500": "#F5BC00",
                "main600": "#C69300",
                "main700": "#A37D00"
            },
            "green": {
                "main100": "#DCF9E7",
                "main200": "#BDF0CF",
                "main300": "#A8F0C2",
                "main500": "#25D366",
                "main600": "#1FA352",
                "main700": "#1C9C4B"
            },
            "blue": {
                "main100": "#D6F4FF",
                "main200": "#B2E9FF",
                "main300": "#99E4FF",
                "main500": "#00AFF0",
                "main600": "#008CC0",
                "main700": "#0078A3"
            },
            "red": {
                "main100": "#FBE1DA",
                "main200": "#F8C1B6",
                "main300": "#F5B53A",
                "main500": "#E14318",
                "main600": "#C23814",
                "main700": "#A63211"
            },
            "pink": {
                "main100": "#FFD6F1",
                "main200": "#FFB8E8",
                "main300": "#FF99DD",
                "main500": "#FF00A9",
                "main600": "#D60090",
                "main700": "#B8007A"
            },
            "purple": {
                "main100": "#FFD6FF",
                "main200": "#F0B3F0",
                "main300": "#FF99FF",
                "main500": "#800080",
                "main600": "#660066",
                "main700": "#520052"
            }
        }
    }
}
