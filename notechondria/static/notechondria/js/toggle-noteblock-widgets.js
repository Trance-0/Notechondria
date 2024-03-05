$(document).ready(function () {
    // since the script will be activate multiple time with in the same page, we need to do reg for each, sample regex:https://stackoverflow.com/questions/11173188/jquery-select-id-with-word-as-prefix-and-counter-as-suffix
    // console.log($('select[id^="nb"][id$="id_block_type"]'));
    $('select[id^="nb"][id$="id_block_type"]').filter(
        function(){
            // console.log(this.id);
            var prefix=this.id.match(/^nb_\d+_/)[0];
            // console.log(prefix);
            var blockType = $("#"+prefix+"id_block_type").find(":selected").val();
            toggleWidgets(blockType,prefix);
        });

    // the default is for create_noteblock_htmx
    var blockType = $("#id_block_type").find(":selected").val();
    // console.log(blockType);
    toggleWidgets(blockType);
    // add class to widget
    $("#id_is_AI_generated").parent().addClass("form-check");

    // section for edit_noteblock_htmx, id given by "nb_{noteid}_field_name"
});

$('select[id^="nb"][id$="id_block_type"]').on("change", function () {
    var prefix=this.id.match(/^nb_\d+_/)[0];
    // console.log(prefix);
    var blockType = $("#"+prefix+"id_block_type").find(":selected").val();
    toggleWidgets(blockType,prefix);
    // alert("change detected");
});

$("#id_block_type").on("change", function () {
    toggleWidgets(this.value);
    // alert("change detected");
});

function toggleWidgets(option,prefix="") {
    // hide all 
    $(".type-based-widgets").parent().hide();
    $("#"+prefix+"id_text").attr("rows", "6");
    // console.log(option);
    // show by condition
    switch (option) {
        case "C":
            $("#"+prefix+"id_coding_language_choice").parent().show();
            break;
        case "T":
            $("#"+prefix+"id_text").attr("rows", "1");
            break;
        case "I":
            $("#"+prefix+"id_text").attr("rows", "1");
            $("#"+prefix+"id_image").parent().show();
            break;
        case "F":
            $("#"+prefix+"id_text").attr("rows", "1");
            $("#"+prefix+"id_file").parent().show();
            break;
        case "U":
            $("#"+prefix+"id_text").attr("rows", "1");
            break;
        case "S":
            $("#"+prefix+"id_text").attr("rows", "3");
    }
}