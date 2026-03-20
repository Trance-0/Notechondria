$(document).ready(function () {
    // since the script will be activate multiple time with in the same page, we need to do reg for each, sample regex:https://stackoverflow.com/questions/11173188/jquery-select-id-with-word-as-prefix-and-counter-as-suffix
    // console.log($('select[id^="nb"][id$="id_block_type"]'));
    $('select[id^="nb"][id$="id_block_type"]').filter(
        function(){
            // console.log(this.id);
            var prefix=this.id.match(/^nb_\d+_/)[0];
            // console.log(prefix);
            var block= $("#"+prefix+"id_block_type")
            var blockType = block.find(":selected").val();
            // console.log(blockType);
            toggleWidgets(block.parent().parent(),blockType,prefix);
        });

    // the default is for create_noteblock_htmx
    var block=$("#id_block_type")
    var blockType = block.find(":selected").val();
    if (blockType!==undefined){
        // console.log("model form block type: "+blockType);
        toggleWidgets(block.parent().parent(),blockType);
        // add class to widget
        $("#id_is_AI_generated").parent().addClass("form-check");
    }
    // section for edit_noteblock_htmx, id given by "nb_{noteid}_field_name"
});

$('select[id^="nb"][id$="id_block_type"]').on("change", function () {
    var prefix=this.id.match(/^nb_\d+_/)[0];
    // console.log(prefix);
    var block=$("#"+prefix+"id_block_type")
    var blockType = block.find(":selected").val();
    // console.log("change on block form detected");
    toggleWidgets(block.parent().parent(),blockType,prefix);
});

$("#id_block_type").on("change", function () {
    // console.log("change on model form detected");
    toggleWidgets(this.parent().parent(),this.value);
});

function toggleWidgets(rootDiv,option,prefix="") {
    // console.log("received parent: "+rootDiv.className)
    // hide all 
    rootDiv.find(".type-based-widgets").parent().hide();
    $("#"+prefix+"id_text").attr("rows", "6");
    // console.log("received option and prefix:"+option+prefix);
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
            $("#"+prefix+"id_url").parent().show();
            break;
        case "S":
            $("#"+prefix+"id_text").attr("rows", "3");
            $("#"+prefix+"id_subtitle_choice").parent().show();
    }
}