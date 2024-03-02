$(document).ready(function () {
    $("#createQuickNoteBlockModal").modal("show");
    var blockType = $("#id_block_type").find(":selected").val();
    // console.log(blockType);
    toggleWidgets(blockType);
    // add class to widget
    $("#id_is_AI_generated").parent().addClass("form-check");
});
$("#id_block_type").on("change", function () {
    toggleWidgets(this.value);
    // alert("change detected");
});

function toggleWidgets(option) {
    // hide all 
    $(".type-based-widgets").parent().hide();
    $("#id_text").attr("rows", "6");
    // show by condition
    switch (option) {
        case "C":
            $("#id_code_language_choice").parent().show();
            break;
        case "T":
            $("#id_text").attr("rows", "1");
        case "I":
            $("#id_text").attr("rows", "1");
            $("#id_image").parent().show();
            break;
        case "F":
            $("#id_text").attr("rows", "1");
            $("#id_file").parent().show();
            break;
        case "U":
            $("#id_text").attr("rows", "1");
            break;
        case "S":
            $("#id_text").attr("rows", "3");
    }
}