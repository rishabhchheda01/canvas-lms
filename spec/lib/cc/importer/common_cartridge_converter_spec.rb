# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

require_relative "../cc_spec_helper"

require "nokogiri"

describe "Standard Common Cartridge importing" do
  before(:once) do
    archive_file_path = File.join(File.dirname(__FILE__) + "/../../../fixtures/migration/cc_full_test.zip")
    unzipped_file_path = create_temp_dir!
    converter = CC::Importer::Standard::Converter.new(export_archive_path: archive_file_path, course_name: "oi", base_download_dir: unzipped_file_path)
    converter.export
    @course_data = converter.course.with_indifferent_access
    @course_data["all_files_export"] ||= {}
    @course_data["all_files_export"]["file_path"] = @course_data["all_files_zip"]

    @course = course_factory
    @migration = ContentMigration.create(context: @course)
    @migration.migration_settings[:migration_ids_to_import] = { copy: {} }
    Importers::CourseContentImporter.import_content(@course, @course_data, nil, @migration)
  end

  it "imports webcontent" do
    expect(@course.attachments.count).to eq 10
    atts = %w[I_00001_R I_00006_Media I_media_R f3 f4 f5 8612e3db71e452d5d2952ff64647c0d8 I_00003_R_IMAGERESOURCE 7acb90d1653008e73753aa2cafb16298 6a35b0974f59819404dc86d48fe39fc3]
    atts.each do |mig_id|
      expect(@course.attachments.where(migration_id: mig_id)).to be_exists
    end
  end

  it "imports files as assignments with intended_use set" do
    assignment = @course.assignments.where(migration_id: "f5").first
    att = @course.attachments.where(migration_id: "8612e3db71e452d5d2952ff64647c0d8").first
    expect(assignment.description).to match_ignoring_whitespace(%(<img src="/courses/#{@course.id}/files/#{att.id}/preview">))
    expect(assignment.title).to eq "Assignment 2"
  end

  it "imports discussion topics" do
    expect(@course.discussion_topics.count).to eq 2
    file1_id = @course.attachments.where(migration_id: "I_media_R").first.id
    file2_id = @course.attachments.where(migration_id: "I_00006_Media").first.id

    dt = @course.discussion_topics.where(migration_id: "I_00006_R").first
    expect(dt.message).to match_ignoring_whitespace(%(Your face is ugly. <br><img src="/courses/#{@course.id}/files/#{file1_id}/preview">))
    dt.attachment_id = file2_id

    dt = @course.discussion_topics.where(migration_id: "I_00009_R").first
    expect(dt.message).to match_ignoring_whitespace(%(Monkeys: Go!\n<ul>\n<li>\n<a href="/courses/#{@course.id}/files/#{file2_id}/preview">angry_person.jpg</a>\n</li>\n<li>\n<a href="/courses/#{@course.id}/files/#{file1_id}/preview">smiling_dog.jpg</a>\n</li>\n</ul>))
  end

  # This also tests the WebLinks, they are just content tags and don't have their own class
  it "imports modules from organization" do
    expect(@course.context_modules.count).to eq 3
    expect(@course.context_modules.map(&:position)).to eql [1, 2, 3]

    mod1 = @course.context_modules.where(migration_id: "I_00000").first
    expect(mod1.name).to eq "Your Mom, Research, & You"
    tag = mod1.content_tags[0]
    expect(tag.content_type).to eq "Attachment"
    expect(tag.content_id).to eq @course.attachments.where(migration_id: "I_00001_R").first.id
    expect(tag.indent).to eq 0
    tag = mod1.content_tags[1]
    expect(tag.content_type).to eq "ContextModuleSubHeader"
    expect(tag.title).to eq "Study Guide"
    expect(tag.migration_id).to eq "I_00002"
    expect(tag.indent).to eq 0
    index = 2
    if Qti.qti_enabled?
      tag = mod1.content_tags[index]
      expect(tag.title).to eq "Pretest"
      expect(tag.content_type).to eq "Quizzes::Quiz"
      expect(tag.content_id).to eq @course.quizzes.where(migration_id: "I_00003_R").first.id
      expect(tag.indent).to eq 1
      index += 1
    end
    tag = mod1.content_tags[index]
    expect(tag.content_type).to eq "ExternalUrl"
    expect(tag.title).to eq "Wikipedia - Your Mom"
    expect(tag.url).to eq "http://en.wikipedia.org/wiki/Maternal_insult"
    expect(tag.indent).to eq 0

    mod1 = @course.context_modules.where(migration_id: "m2").first
    expect(mod1.name).to eq "Attachment module"
    expect(mod1.content_tags.count).to eq 5
    tag = mod1.content_tags[0]
    expect(tag.content_type).to eq "Attachment"
    expect(tag.content_id).to eq @course.attachments.where(migration_id: "f3").first.id
    expect(tag.indent).to eq 0
    tag = mod1.content_tags[1]
    expect(tag.content_type).to eq "ContextModuleSubHeader"
    expect(tag.title).to eq "Sub-Folder"
    expect(tag.indent).to eq 0
    tag = mod1.content_tags[2]
    expect(tag.content_type).to eq "Attachment"
    expect(tag.content_id).to eq @course.attachments.where(migration_id: "f4").first.id
    expect(tag.indent).to eq 1
    tag = mod1.content_tags[3]
    expect(tag.content_type).to eq "ContextModuleSubHeader"
    expect(tag.title).to eq "Sub-Folder 2"
    expect(tag.indent).to eq 1
    tag = mod1.content_tags[4]
    expect(tag.content_type).to eq "Assignment"
    expect(tag.content_id).to eq @course.assignments.where(migration_id: "f5").first.id
    expect(tag.indent).to eq 2

    mod1 = @course.context_modules.where(migration_id: "m3").first
    expect(mod1.name).to eq "Misc Module"
    expect(mod1.content_tags.count).to eq 4
    tag = mod1.content_tags[0]
    expect(tag.content_type).to eq "ExternalUrl"
    expect(tag.title).to eq "Wikipedia - Sigmund Freud"
    expect(tag.url).to eq "http://en.wikipedia.org/wiki/Sigmund_Freud"
    expect(tag.indent).to eq 0
    tag = mod1.content_tags[1]
    expect(tag.content_type).to eq "DiscussionTopic"
    expect(tag.title).to eq "Talk about the issues"
    expect(tag.content_id).to eq @course.discussion_topics.where(migration_id: "I_00009_R").first.id
    expect(tag.indent).to eq 0
    tag = mod1.content_tags[2]
    expect(tag.content_type).to eq "ContextExternalTool"
    expect(tag.title).to eq "BLTI Test"
    expect(tag.url).to eq "http://www.imsglobal.org/developers/BLTI/tool.php"
    expect(tag.indent).to eq 0
    tag = mod1.content_tags[3]
    expect(tag.content_type).to eq "Assignment"
    expect(tag.title).to eq "BLTI Assignment Test"
    expect(tag.content_id).to eq @course.assignments.where(migration_id: "I_00011_R").first.id
    expect(tag.indent).to eq 0
  end

  it "imports external tools" do
    expect(@course.context_external_tools.count).to eq 2
    et = @course.context_external_tools.where(migration_id: "I_00010_R").first
    expect(et.name).to eq "BLTI Test"
    expect(et.url).to eq "http://www.imsglobal.org/developers/BLTI/tool.php"
    expect(et.settings[:custom_fields]).to eq({ "key1" => "value1", "key2" => "value2" })
    expect(et.settings[:vendor_extensions]).to eq [{ platform: "my.lms.com", custom_fields: { "key" => "value" } }, { platform: "your.lms.com", custom_fields: { "key" => "value", "key2" => "value2" } }].map(&:with_indifferent_access)
    expect(@migration.warnings.member?("The security parameters for the external tool \"#{et.name}\" may need to be set in Course Settings.")).to be_truthy

    et = @course.context_external_tools.where(migration_id: "I_00011_R").first
    expect(et.name).to eq "BLTI Assignment Test"
    expect(et.url).to eq "http://www.imsglobal.org/developers/BLTI/tool2.php"
    expect(et.settings[:custom_fields]).to eq({})
    expect(et.settings[:vendor_extensions]).to eq [].map(&:with_indifferent_access)
    expect(@migration.warnings.member?("The security parameters for the external tool \"#{et.name}\" may need to be set in Course Settings.")).to be_truthy

    # That second tool had the assignment flag set, so an assignment for it should have been created
    asmnt = @course.assignments.where(migration_id: "I_00011_R").first
    expect(asmnt).not_to be_nil
    expect(asmnt.points_possible).to eq 15.5
    expect(asmnt.external_tool_tag.url).to eq et.url
    expect(asmnt.external_tool_tag.content_type).to eq "ContextExternalTool"
  end

  it "imports assessment data" do
    if Qti.qti_enabled?
      quiz = @course.quizzes.where(migration_id: "I_00003_R").first
      expect(quiz.active_quiz_questions.size).to eq 11
      expect(quiz.title).to eq "Pretest"
      expect(quiz.quiz_type).to eq "assignment"
      expect(quiz.allowed_attempts).to eq 2
      expect(quiz.time_limit).to eq 120

      question = quiz.active_quiz_questions.first
      expect(question.question_data[:points_possible]).to eq 2

      bank = @course.assessment_question_banks.where(migration_id: "I_00004_R_QDB_1").first
      expect(bank.assessment_questions.count).to eq 11
      expect(bank.title).to eq "QDB_1"
    else
      skip("Can't import assessment data with python QTI tool.")
    end
  end

  it "imports assessment data into an active question bank" do
    if Qti.qti_enabled?
      bank = @course.assessment_question_banks.where(migration_id: "I_00004_R_QDB_1").first
      expect(bank.assessment_questions.count).to eq 11
      bank.destroy
      bank.reload
      expect(bank.workflow_state).to eq "deleted"

      @migration = ContentMigration.create(context: @course)
      @migration.migration_settings[:migration_ids_to_import] = { copy: {} }
      Importers::CourseContentImporter.import_content(@course, @course_data, nil, @migration)

      bank = @course.assessment_question_banks.active.where(migration_id: "I_00004_R_QDB_1").first
      expect(bank).not_to be_nil

      expect(bank.assessment_questions.count).to eq 11
    else
      skip("Can't import assessment data with python QTI tool.")
    end
  end

  it "finds update urls in questions" do
    if Qti.qti_enabled?
      q = @course.assessment_questions.where(migration_id: "I_00003_R_QUE_104045").first

      expect(q.question_data[:question_text]).to match %r{/assessment_questions/#{q.id}/files/\d+/}
      expect(q.question_data[:answers].first[:html]).to match %r{/assessment_questions/#{q.id}/files/\d+/}
      expect(q.question_data[:answers].first[:comments_html]).to match %r{/assessment_questions/#{q.id}/files/\d+/}
    else
      skip("Can't import assessment data with python QTI tool.")
    end
  end

  context "re-importing the cartridge" do
    append_before do
      @migration2 = ContentMigration.create(context: @course)
      @migration2.migration_settings[:migration_ids_to_import] = { copy: {} }
      Importers::CourseContentImporter.import_content(@course, @course_data, nil, @migration2)
    end

    it "imports webcontent" do
      expect(@course.attachments.active.count).to eq 10
      mig_ids = %w[I_00001_R I_00006_Media I_media_R f3 f4 I_00003_R_IMAGERESOURCE 7acb90d1653008e73753aa2cafb16298 6a35b0974f59819404dc86d48fe39fc3]
      mig_ids.each do |mig_id|
        atts = @course.attachments.where(migration_id: mig_id).to_a
        expect(atts.length).to eq 1
        expect(atts.first.file_state).to eq "available"
      end
    end

    it "points to new attachment from module" do
      expect(@course.context_modules.count).to eq 3

      mod1 = @course.context_modules.where(migration_id: "I_00000").first
      expect(mod1.content_tags.count).to eq(Qti.qti_enabled? ? 9 : 7)
      expect(mod1.name).to eq "Your Mom, Research, & You"
      tag = mod1.content_tags[0]
      expect(tag.content_type).to eq "Attachment"
      expect(tag.content_id).to eq @course.attachments.not_deleted.where(migration_id: "I_00001_R").first.id
    end
  end

  context "selective import" do
    it "selectively imports files" do
      @course = course_factory
      @migration = ContentMigration.create(context: @course)
      @migration.migration_settings[:migration_ids_to_import] = {
        copy: { "discussion_topics" => { "I_00006_R" => true },
                "everything" => "0",
                "folders" =>
                          { "I_00006_Media" => true,
                            "6a35b0974f59819404dc86d48fe39fc3" => true,
                            "I_00001_R" => true },
                "all_quizzes" => "1",
                "all_context_external_tools" => "0",
                "all_groups" => "0",
                "all_context_modules" => "0",
                "all_rubrics" => "0",
                "assessment_questions" => "1",
                "all_wiki_pages" => "0",
                "all_attachments" => "0",
                "all_assignments" => "1",
                "topic_entries" => { "undefined" => true },
                "context_external_tools" => { "I_00011_R" => true },
                "shift_dates" => "0",
                "all_discussion_topics" => "0",
                "all_announcements" => "0",
                "attachments" =>
                          { "I_00006_Media" => true,
                            "7acb90d1653008e73753aa2cafb16298" => true,
                            "6a35b0974f59819404dc86d48fe39fc3" => true,
                            "I_00003_R_IMAGERESOURCE" => true,
                            "I_00001_R" => true },
                "context_modules" => { "I_00000" => true },
                "all_assignment_groups" => "0" }
      }.with_indifferent_access

      Importers::CourseContentImporter.import_content(@course, @course_data, nil, @migration)

      expect(@course.attachments.count).to eq 5
      expect(@course.context_external_tools.count).to eq 1
      expect(@course.context_external_tools.first.migration_id).to eq "I_00011_R"
      expect(@course.context_modules.count).to eq 1
      expect(@course.context_modules.first.migration_id).to eq "I_00000"
      expect(@course.wiki_pages.count).to eq 0
      expect(@course.discussion_topics.count).to eq 1
      expect(@course.discussion_topics.first.migration_id).to eq "I_00006_R"
    end

    it "does not import all attachments if :files does not exist" do
      @course = course_factory
      @migration = ContentMigration.create(context: @course)
      @migration.migration_settings[:migration_ids_to_import] = {
        copy: { "everything" => "0" }
      }.with_indifferent_access

      Importers::CourseContentImporter.import_content(@course, @course_data, nil, @migration)

      expect(@course.attachments.count).to eq 0
    end
  end

  context "position conflicts" do
    append_before do
      @import_json =
        {
          "modules" => [
            {
              "title" => "monkeys",
              "position" => 1,
              "migration_id" => "m_monkeys"
            },
            {
              "title" => "ponies",
              "position" => 2,
              "migration_id" => "m_ponies"
            },
            {
              "title" => "last",
              "position" => 3,
              "migration_id" => "m_last"
            }
          ],
          "assignment_groups" => [
            {
              "title" => "monkeys",
              "position" => 1,
              "migration_id" => "ag_monkeys"
            },
            {
              "title" => "ponies",
              "position" => 2,
              "migration_id" => "ag_ponies"
            },
            {
              "title" => "last",
              "position" => 3,
              "migration_id" => "ag_last"
            }
          ]
        }
    end

    it "fixes position conflicts for modules" do
      @course = course_factory

      mod1 = @course.context_modules.create name: "ponies"
      mod1.position = 1
      mod1.migration_id = "m_ponies"
      mod1.save!

      mod2 = @course.context_modules.create name: "monsters"
      mod2.migration_id = "m_monsters"
      mod2.position = 2
      mod2.save!

      @migration = ContentMigration.create(context: @course)
      @migration.migration_settings[:migration_ids_to_import] = {
        copy: {
          "everything" => "0",
          "all_context_modules" => "1"
        }
      }
      Importers::CourseContentImporter.import_content(@course, @import_json, nil, @migration)

      mods = @course.context_modules.to_a
      expect(mods.map(&:position)).to eql [1, 2, 3, 4]
      expect(mods.map(&:name)).to eql %w[ponies monsters monkeys last]
    end

    it "fixes position conflicts for assignment groups" do
      @course = course_factory

      ag1 = @course.assignment_groups.create name: "ponies"
      ag1.position = 1
      ag1.migration_id = "ag_ponies"
      ag1.save!

      ag2 = @course.assignment_groups.create name: "monsters"
      ag2.position = 2
      ag2.migration_id = "ag_monsters"
      ag2.save!

      @migration = ContentMigration.create(context: @course)
      @migration.migration_settings[:migration_ids_to_import] = {
        copy: {
          "everything" => "0",
          "all_assignment_groups" => "1"
        }
      }
      Importers::CourseContentImporter.import_content(@course, @import_json, nil, @migration)

      ags = @course.assignment_groups.to_a
      expect(ags.map(&:position)).to eql [1, 2, 3, 4]
      expect(ags.map(&:name)).to eql %w[monkeys ponies monsters last]
    end
  end

  context "sub-modules" do
    it "list submodules in the overview" do
      overview = JSON.parse(File.read(@course_data["overview_file_path"]))
      root_mod = overview["modules"][1]
      sub_mod = root_mod["submodules"].first
      expect(sub_mod["title"]).to eq "Sub-Folder"
      expect(sub_mod["migration_id"]).to eq "sf1"

      sub_mod2 = sub_mod["submodules"].first
      expect(sub_mod2["title"]).to eq "Sub-Folder 2"
      expect(sub_mod2["migration_id"]).to eq "sf2"
    end

    it "imports submodules individually if selected" do
      course_factory
      @migration = ContentMigration.create(context: @course)
      @migration.migration_settings[:migration_ids_to_import] = {
        copy: { "context_modules" => { "sf2" => "1" } }
      }
      Importers::CourseContentImporter.import_content(@course, @course_data, nil, @migration)

      expect(@course.context_modules.count).to eq 1
      mod = @course.context_modules.first

      expect(mod.name).to eq "Sub-Folder 2" # imports as a top-level module

      expect(mod.content_tags.count).to eq 1
      tag = mod.content_tags.first
      expect(tag.title).to eq "Assignment 2"
      expect(tag.content).to be_present
    end
  end
end

describe "More Standard Common Cartridge importing" do
  before do
    @converter = get_standard_converter
    @copy_to = course_model
    @copy_to.name = "alt name"
    @copy_to.course_code = "alt name"

    @migration = ContentMigration.new
    allow(@migration).to receive_messages(to_import: nil, context: @copy_to, import_object?: true)
    allow(@migration).to receive(:add_imported_item)
  end

  it "properly handles top-level resource references" do
    orgs = <<~XML
      <organizations>
        <organization structure="rooted-hierarchy" identifier="org_1">
          <item identifier="LearningModules">
            <item identifier="m1">
              <title>some module</title>
              <item identifier="ct2" identifierref="w1">
                <title>some page</title>
              </item>
            </item>
            <item identifier="ct5" identifierref="f3">
              <title>Super exciting!</title>
            </item>
            <item identifier="m2">
              <title>next module</title>
            </item>
            <item identifier="ct6" identifierref="f4">
              <title>test answers</title>
            </item>
            <item identifier="ct7" identifierref="f5">
              <title>test answers</title>
            </item>
          </item>
        </organization>
      </organizations>
    XML

    # convert to json
    # pretend there were resources for the referenced items
    @converter.resources = { "w1" => { type: "webcontent" }, "f3" => { type: "webcontent" }, "f4" => { type: "webcontent" }, "f5" => { type: "webcontent" }, }
    doc = Nokogiri::XML(orgs)
    hash = @converter.convert_organizations(doc)

    # make all the fake attachments for the module items to link to
    unfiled_folder = Folder.unfiled_folder(@copy_to)
    w1 = Attachment.create!(filename: "w1.html", uploaded_data: StringIO.new("w1"), folder: unfiled_folder, context: @copy_to)
    w1.migration_id = "w1"
    w1.save
    f3 = Attachment.create!(filename: "f3.html", uploaded_data: StringIO.new("f3"), folder: unfiled_folder, context: @copy_to)
    f3.migration_id = "f3"
    f3.save
    f4 = Attachment.create!(filename: "f4.html", uploaded_data: StringIO.new("f4"), folder: unfiled_folder, context: @copy_to)
    f4.migration_id = "f4"
    f4.save
    f5 = Attachment.create!(filename: "f5.html", uploaded_data: StringIO.new("f5"), folder: unfiled_folder, context: @copy_to)
    f5.migration_id = "f5"
    f5.save

    # import json into new course
    hash = hash.map(&:with_indifferent_access)
    Importers::ContextModuleImporter.process_migration({ "modules" => hash }, @migration)
    @copy_to.save!

    expect(@copy_to.context_modules.count).to eq 3

    mod1 = @copy_to.context_modules.where(migration_id: "m1").first
    expect(mod1.name).to eq "some module"
    expect(mod1.content_tags.count).to eq 1
    expect(mod1.position).to eq 1
    tag = mod1.content_tags.last
    expect(tag.content_id).to eq w1.id
    expect(tag.content_type).to eq "Attachment"
    expect(tag.indent).to eq 0

    mod2 = @copy_to.context_modules.where(migration_id: "misc_module_top_level_items").first
    expect(mod2.name).to eq "Misc Module"
    expect(mod2.content_tags.count).to eq 3
    expect(mod2.position).to eq 2
    tag = mod2.content_tags.first
    expect(tag.content_id).to eq f3.id
    expect(tag.content_type).to eq "Attachment"
    expect(tag.indent).to eq 0
    tag = mod2.content_tags[1]
    expect(tag.content_id).to eq f4.id
    expect(tag.content_type).to eq "Attachment"
    expect(tag.indent).to eq 0
    tag = mod2.content_tags[2]
    expect(tag.content_id).to eq f5.id
    expect(tag.content_type).to eq "Attachment"
    expect(tag.indent).to eq 0

    mod3 = @copy_to.context_modules.where(migration_id: "m2").first
    expect(mod3.name).to eq "next module"
    expect(mod3.content_tags.count).to eq 0
    expect(mod3.position).to eq 3
  end

  it "handles back-slashed paths" do
    resources = <<~XML
      <resources>
        <resource href="a1\\a1.html" identifier="a1" type="webcontent" intendeduse="assignment">
          <file href="a1\\a1.html"/>
        </resource>
        <resource identifier="w1" type="webcontent">
          <file href="w1\\w1.html"/>
          <file href="w1\\w2.html"/>
        </resource>
        <resource identifier="q1" type="imsqti_xmlv1p2/imscc_xmlv1p2/assessment">
          <file href="q1\\q1.xml"/>
        </resource>
      </resources>
    XML

    doc = Nokogiri::XML(resources)
    @converter.get_all_resources(doc)
    expect(@converter.resources["a1"][:href]).to eq "a1/a1.html"
    expect(@converter.resources["w1"][:files].first[:href]).to eq "w1/w1.html"
    expect(@converter.resources["w1"][:files][1][:href]).to eq "w1/w2.html"
    expect(@converter.resources["q1"][:files].first[:href]).to eq "q1/q1.xml"
  end
end

describe "non-ASCII attachment names" do
  it "does not fail to create all_files.zip" do
    archive_file_path = File.join(File.dirname(__FILE__) + "/../../../fixtures/migration/unicode-filename-test-export.imscc")
    @converter = CC::Importer::Standard::Converter.new(export_archive_path: archive_file_path)
    expect { @converter.export }.not_to raise_error
    contents = ["course_settings/assignment_groups.xml",
                "course_settings/canvas_export.txt",
                "course_settings/course_settings.xml",
                "course_settings/files_meta.xml",
                "course_settings/syllabus.html",
                "abc.txt",
                "molé.txt",
                "xyz.txt"]
    expect(@converter.course[:file_map].values.pluck(:path_name).sort).to eq contents.sort

    Zip::File.open File.join(@converter.base_export_dir, "all_files.zip") do |zipfile|
      zipcontents = zipfile.entries.map(&:name)
      expect(contents - zipcontents).to eql []
    end
  end
end

describe "LTI tool combination" do
  before(:once) do
    archive_file_path = File.join(File.dirname(__FILE__) + "/../../../fixtures/migration/cc_lti_combine_test.zip")
    unzipped_file_path = create_temp_dir!
    converter = CC::Importer::Standard::Converter.new(export_archive_path: archive_file_path, course_name: "oi", base_download_dir: unzipped_file_path)
    converter.export
    @course_data = converter.course.with_indifferent_access
    @course_data["all_files_export"] ||= {}
    @course_data["all_files_export"]["file_path"] = @course_data["all_files_zip"]

    @course = course_factory
    @migration = ContentMigration.create(context: @course)
    @migration.migration_type = "common_cartridge_importer"
    @migration.migration_settings[:migration_ids_to_import] = { copy: {} }
    Importers::CourseContentImporter.import_content(@course, @course_data, nil, @migration)
  end

  it "combines lti tools in cc packages when possible" do
    expect(@course.context_external_tools.count).to eq 2
    expect(@course.context_external_tools.map(&:migration_id).sort).to eq ["TOOL_1", "TOOL_3"]

    combined_tool = @course.context_external_tools.where(migration_id: "TOOL_1").first
    expect(combined_tool.domain).to eq "www.example.com"
    other_tool = @course.context_external_tools.where(migration_id: "TOOL_3").first
    expect(@course.context_module_tags.count).to eq 5

    combined_tags = @course.context_module_tags.select { |ct| ct.url.start_with?("https://www.example.com") }
    expect(combined_tags.count).to eq 4
    combined_tags.each do |tag|
      expect(tag.content).to eq combined_tool
    end

    other_tag = (@course.context_module_tags.to_a - combined_tags).first
    expect(other_tag.url.start_with?("https://www.differentdomainexample.com")).to be_truthy
    expect(other_tag.content).to eq other_tool
  end
end

describe "other cc files" do
  def import_cc_file(filename)
    archive_file_path = File.join(File.dirname(__FILE__) + "/../../../fixtures/migration/#{filename}")
    unzipped_file_path = create_temp_dir!

    @course = course_factory
    @migration = ContentMigration.create(context: @course)
    @migration.migration_type = "common_cartridge_importer"
    @migration.migration_settings[:migration_ids_to_import] = { copy: {} }

    converter = CC::Importer::Standard::Converter.new(export_archive_path: archive_file_path,
                                                      course_name: "oi",
                                                      base_download_dir: unzipped_file_path,
                                                      content_migration: @migration)
    converter.export
    @course_data = converter.course.with_indifferent_access
    Importers::CourseContentImporter.import_content(@course, @course_data, nil, @migration)
  end

  describe "cc assignment extensions" do
    before(:once) do
      import_cc_file("cc_assignment_extension.zip")
    end

    it "parses canvas data from cc extension" do
      expect(@migration.migration_issues.count).to eq 0

      att = @course.attachments.where(migration_id: "ieee173de6109d169c627d07bedae0595").first

      expect(@course.assignments.count).to eq 2
      assignment1 = @course.assignments.where(migration_id: "icd613a5039d9a1539e100058efe44242").first
      expect(assignment1.grading_type).to eq "pass_fail"
      expect(assignment1.points_possible).to eq 20
      expect(assignment1.description).to include("<img src=\"/courses/#{@course.id}/files/#{att.id}/preview\" alt=\"dana_small.png\">")
      expect(assignment1.submission_types).to eq "online_text_entry,online_url,media_recording,online_upload" # overridden

      assignment2 = @course.assignments.where(migration_id: "icd613a5039d9a1539e100058efe44242copy").first
      expect(assignment2.grading_type).to eq "points"
      expect(assignment2.points_possible).to eq 21
      expect(assignment2.description).to include("hi, the canvas meta stuff does not have submission types")
      expect(assignment2.submission_types).to eq "online_upload,online_text_entry,online_url"
    end
  end

  describe "cc optional html file to page conversation" do
    it "does some possibly broken converting" do
      Account.default.enable_feature!(:common_cartridge_page_conversion)
      import_cc_file("cc_file_to_page_test.zip")
      img = @course.attachments.where(migration_id: "I_00001_R_1").first

      page = @course.wiki_pages.where(migration_id: "I_00001_R").first
      expect(page.title).to eq "Some kind of file or page thingy"
      expect(page.body).to match_ignoring_whitespace("<p>THis is an image or something <img src=\"/courses/#{@course.id}/files/#{img.id}/preview\"></p>")

      tag = @course.context_module_tags.first
      expect(tag.content).to eq page
    end

    it "deals with screwy $IMS-CC-FILEBASE$../ links to possibly missing files" do
      Account.default.enable_feature!(:common_cartridge_page_conversion)
      import_cc_file("cc_dotdot_madness.zip")

      file = @course.attachments.find_by(migration_id: "101dabe4f8c7b12a49a491e7db2e0830")
      page = @course.wiki_pages.find_by(migration_id: "ELEMENT_8636_1628897")
      expect(page.body).to include "/courses/#{@course.id}/files/#{file.id}"

      migration = @course.content_migrations.last
      expect(migration.migration_issues.map(&:description)).to include "Missing links found in imported content - Wiki Page body"
    end

    it "justs bring them over as files without the feature" do
      import_cc_file("cc_file_to_page_test.zip")
      expect(@course.wiki_pages.count).to eq 0

      att = @course.attachments.where(migration_id: "I_00001_R").first
      tag = @course.context_module_tags.first
      expect(tag.content).to eq att
    end
  end

  describe "cc pattern match questions" do
    it "produces a warning" do
      next unless Qti.qti_enabled?

      import_cc_file("cc_pattern_match.zip")
      expect(@migration.migration_issues.first.description).to include("This package includes the question type, Pattern Match")
    end
  end

  describe "cc unsupported resource types" do
    it "produces warnings" do
      next unless Qti.qti_enabled?

      import_cc_file("cc_unsupported_resources.zip")
      issues = @migration.migration_issues.pluck(:description)
      expect(issues.any? { |i| i.include?("This package includes APIP file(s)") }).to be_truthy
      expect(issues.any? { |i| i.include?("This package includes IWB file(s)") }).to be_truthy
      expect(issues.any? { |i| i.include?("This package includes EPub3 file(s)") }).to be_truthy
    end
  end

  describe "cc syllabus intendeduse" do
    it "imports" do
      import_cc_file("cc_syllabus.zip")
      expect(@course.reload.syllabus_body).to include("<p>beep beep</p>")
    end
  end

  describe "empty file link name inference" do
    it "adds the file name to empty links in html content" do
      import_cc_file("cc_empty_link.zip")
      assmt = @course.assignments.where(migration_id: "assignment1").first
      file = @course.attachments.where(migration_id: "file1").first
      doc = Nokogiri::HTML::DocumentFragment.parse(assmt.description)
      link = doc.at_css("a")
      expect(link.attr("href")).to include("courses/#{@course.id}/files/#{file.id}")
      expect(link.text.strip).to eq file.display_name
    end
  end
end
