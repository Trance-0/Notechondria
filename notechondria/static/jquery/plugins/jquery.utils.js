;!(function($){


    $.fn.classes = function(callback){
        var classes = [];
        $.each(this, function (i, v) {
            var splitClassName = v.className.split(/\s+/);
            for (var j = 0; j < splitClassName.length; j++) {
                var className = splitClassName[j];
                if (-1 === classes.indexOf(className)) {
                    classes.push(className);
                }
            }
        });
        if ('function' === typeof callback) {
            for (var i in classes) {
                callback(classes[i]);
            }
        }
        return classes;
    };

    $.randInt = function(n) {
        return parseInt(Math.random() * n);
    };

    $.string = {};
    $.string.ascii_lowercase = "abcdefghijklmnopqrstuvwxyz";
    $.string.ascii_uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    $.string.ascii_letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    $.string.digits = "0123456789";
    $.string.punctuation = '!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~';
    $.string.printable = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~ \t\n\r\x0b\x0c';

    $.randomString = function(length, choices, prefix){
        length = typeof length != 'undefined' ? length : 8;
        choices = typeof choices != 'undefined' ? choices : $.string.ascii_letters + $.string.digits + $.punctuation
        prefix = typeof prefix !== 'undefined' ? prefix : '';
        var i;
        var choices_length = choices.length;
        var result = prefix;
        for(i=0; i<length; i++){
            result += choices.charAt($.randInt(choices_length));
        }
        return result;
    };
    
    $.randomId = function(length, prefix){
        length = typeof length != 'undefined' ? length : 16;
        prefix = typeof prefix !== 'undefined' ? prefix : 'id';
        return $.randomString(length, $.string.ascii_letters + $.string.digits, prefix);
    };

})(jQuery);
