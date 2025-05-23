export class Styles {
    textColor;
    borderColor;
    backgroundColor;
    textSize;
    borderSize;
    constructor(textColor, borderColor, backgroundColor, textSize, borderSize) {
        this.textColor = textColor;
        this.borderColor = borderColor;
        this.backgroundColor = backgroundColor;
        this.textSize = textSize;
        this.borderSize = borderSize;
    }
    static fromSettings(settings) {
        const textColor = settings.get_string("text-color");
        const borderColor = settings.get_string("border-color");
        const backgroundColor = settings.get_string("background-color");
        const textSize = settings.get_int("text-size");
        const borderSize = settings.get_int("border-size");
        return new Styles(textColor, borderColor, backgroundColor, textSize, borderSize);
    }
}
